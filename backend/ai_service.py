import json
import google.generativeai as genai
import config

class AIService:
    def __init__(self):
        self.api_key = config.GEMINI_API_KEY
        if self.api_key:
            genai.configure(api_key=self.api_key)
        else:
            print("WARNING: GEMINI_API_KEY is not set. AI features will return mock data.")

    def get_embedding(self, text: str, is_query: bool = False) -> list[float]:
        """Generates a vector embedding for the input text."""
        if not self.api_key:
            # Return a mock 3072-dim vector of zeros if no API key is present
            return [0.0] * 3072
            
        task_type = "retrieval_query" if is_query else "retrieval_document"
        try:
            response = genai.embed_content(
                model="models/gemini-embedding-001",
                content=text,
                task_type=task_type
            )
            return response["embedding"]
        except Exception as e:
            print(f"Error generating embedding: {e}")
            raise e

    def get_embeddings_batch(self, texts: list[str]) -> list[list[float]]:
        """Generates vector embeddings for a list of texts in batch, chunking to respect API rate limits."""
        if not self.api_key:
            return [[0.0] * 3072 for _ in texts]
            
        if not texts:
            return []
            
        embeddings = []
        batch_size = 30  # Keep batch size small to avoid hitting rate/token limits per minute
        import time
        
        for i in range(0, len(texts), batch_size):
            batch_texts = texts[i : i + batch_size]
            try:
                response = genai.embed_content(
                    model="models/gemini-embedding-001",
                    content=batch_texts,
                    task_type="retrieval_document"
                )
                embeddings.extend(response["embedding"])
            except Exception as e:
                print(f"Error generating batch embeddings for batch {i // batch_size}: {e}")
                # Fall back to single requests with a safe delay to avoid flooding
                for text in batch_texts:
                    try:
                        embeddings.append(self.get_embedding(text))
                        time.sleep(0.5)
                    except Exception as single_err:
                        print(f"Single embedding request failed: {single_err}")
                        # Defensive: append a zero vector so the rest of the file still succeeds
                        embeddings.append([0.0] * 3072)
            
            # Introduce a 1-second delay between batches to respect Gemini's Free Tier RPM limit
            if i + batch_size < len(texts):
                time.sleep(1.0)
                
        return embeddings

    def generate_summary(self, document_title: str, document_text_sample: str) -> str:
        """Generates a study summary of a document based on text samples."""
        if not self.api_key:
            return f"Mock Summary for {document_title}: This is a placeholder summary. Please configure GEMINI_API_KEY in the backend .env to see AI generated summaries."

        prompt = f"""
You are an expert AI Study Assistant. Write a comprehensive, well-structured study guide and summary for the document: "{document_title}".

Based on this text excerpt from the document:
---
{document_text_sample[:12000]} # Limit size to fit prompt windows comfortably
---

Your study guide should include:
1. **Overview & Main Themes**: A high-level description of what the document covers.
2. **Key Concepts & Definitions**: Bullet points explaining crucial terms or equations.
3. **Core Insights / Takeaways**: Elaborate on the central arguments or points made.
4. **Study Tips / Review Questions**: Recommendations on how to study this material.

Use clear markdown headings, bold text, and bullet points. Make it structured and easy to read.
"""
        try:
            model = genai.GenerativeModel("gemini-flash-latest")
            response = model.generate_content(prompt)
            return response.text
        except Exception as e:
            return f"Error generating summary: {str(e)}"

    def generate_flashcards(self, document_text_sample: str) -> list[dict]:
        """Generates a list of flashcards (question and answer pairs) from document text."""
        if not self.api_key:
            return [
                {"question": "What is the capital of France?", "answer": "Paris"},
                {"question": "How do you define RAG in AI?", "answer": "Retrieval-Augmented Generation"}
            ]

        prompt = f"""
Based on the following document text, generate 8 to 12 high-quality, conceptual flashcards for a student to study.
The questions should test understanding of key concepts, definitions, or equations. The answers should be concise but informative.

Return ONLY a JSON array of flashcards, where each object has exactly two keys: "question" and "answer". Do not include any explanation or markdown formatting other than raw JSON.

Text Excerpt:
---
{document_text_sample[:10000]}
---
"""
        try:
            # Force JSON response output
            model = genai.GenerativeModel(
                "gemini-flash-latest",
                generation_config={"response_mime_type": "application/json"}
            )
            response = model.generate_content(prompt)
            
            # Parse the JSON response
            flashcards = json.loads(response.text)
            
            # Basic validation
            if isinstance(flashcards, list):
                valid_cards = []
                for card in flashcards:
                    if isinstance(card, dict) and "question" in card and "answer" in card:
                        valid_cards.append({
                            "question": str(card["question"]),
                            "answer": str(card["answer"])
                        })
                return valid_cards
            
            return []
        except Exception as e:
            print(f"Error generating flashcards: {e}")
            return []

    def answer_question_with_context(self, question: str, retrieved_chunks: list[dict], chat_history: list[dict] = None) -> str:
        """Answers a user's question relative to retrieved document chunks (RAG)."""
        if not self.api_key:
            return "This is a mock response. Please configure GEMINI_API_KEY in the backend to start chatting with your PDF."

        # Compile the search context
        context_str = ""
        for i, chunk in enumerate(retrieved_chunks):
            doc_title = chunk.get("document_title", "Unknown Document")
            context_str += f"[Source: \"{doc_title}\", Page {chunk['page_number']}]:\n{chunk['text']}\n\n"

        # Compile chat history context
        history_str = ""
        if chat_history:
            for msg in chat_history[-6:]: # Include last 6 messages
                role = "User" if msg["sender"] == "user" else "Assistant"
                history_str += f"{role}: {msg['text']}\n"

        prompt = f"""
You are an AI Study Assistant helper. You are helping a student study their documents.
Answer the user's question using the provided document context below. If the answer is not in the context, use your general knowledge, but clearly state that it is not explicitly mentioned in the documents.
Cite both the document title and page number when giving information from the context.

Document Context:
---
{context_str}
---

Recent Chat History:
{history_str}
User's Question: {question}

Provide a helpful, precise, and friendly answer. Cite the specific book and page number in brackets like ["Biology Textbook", Page 3] when referring to information.
"""
        try:
            model = genai.GenerativeModel("gemini-flash-latest")
            response = model.generate_content(prompt)
            return response.text
        except Exception as e:
            return f"Error generating answer: {str(e)}"

    def perform_text_action(self, text: str, action: str, target_language: str = "Spanish") -> dict:
        """
        Performs an AI text action (explain, summarize, generate_flashcards, generate_quiz, translate)
        on the selected text snippet.
        """
        if not self.api_key:
            # Mock data fallback
            if action == "explain":
                return {"result": f"Mock Explanation: This is an explanation of '{text}'."}
            elif action == "summarize":
                return {"result": f"Mock Summary: A concise summary of '{text}'."}
            elif action == "generate_flashcards":
                return {
                    "result": json.dumps([
                        {"question": f"What does '{text[:30]}...' refer to?", "answer": "This is a mock answer."},
                        {"question": "What is the key concept here?", "answer": "Mock explanation of the core concept."}
                    ])
                }
            elif action == "generate_quiz":
                return {
                    "result": json.dumps([
                        {
                            "question": f"Which of the following is true about '{text[:30]}...'?",
                            "options": ["Option A", "Option B", "Option C", "Option D"],
                            "correct_answer": "Option A"
                        }
                    ])
                }
            elif action == "translate":
                return {"result": f"Mock Translation ({target_language}): [Translated text placeholder]"}
            return {"result": "Unknown action"}

        if action == "explain":
            prompt = f"""
You are an expert AI tutor. Explain the following text snippet in detail. Use simple, clear language. 
Use markdown headings, bullet points, and bold text to structure your response.

Text:
---
{text}
---
"""
            model_name = "gemini-flash-latest"
        elif action == "summarize":
            prompt = f"""
You are an expert AI summarizer. Provide a highly concise bulleted summary of the following text snippet. 
Focus only on the key facts, terms, or concepts.

Text:
---
{text}
---
"""
            model_name = "gemini-flash-latest"
        elif action == "translate":
            prompt = f"""
Translate the following text into {target_language}. Keep the tone and formatting natural. Return ONLY the translated text, do not add any comments or headers.

Text:
---
{text}
---
"""
            model_name = "gemini-flash-latest"
        elif action == "generate_flashcards":
            prompt = f"""
Based on the following text snippet, generate 3 to 5 high-quality conceptual flashcards. 
Return ONLY a JSON array of flashcards, where each object has exactly two keys: "question" and "answer". Do not include any explanation or markdown formatting other than raw JSON.

Text:
---
{text}
---
"""
            model_name = "gemini-flash-latest"
        elif action == "generate_quiz":
            prompt = f"""
Based on the following text snippet, generate 3 to 5 multiple-choice questions for a student quiz.
Return ONLY a JSON array of questions, where each object has exactly three keys: 
1. "question": The question text.
2. "options": An array of exactly 4 choices/options.
3. "correct_answer": The exact string of the correct choice from the options array.

Do not include any explanation or markdown formatting other than raw JSON.

Text:
---
{text}
---
"""
            model_name = "gemini-flash-latest"
        else:
            return {"error": f"Invalid action: {action}"}

        try:
            if action in ["generate_flashcards", "generate_quiz"]:
                model = genai.GenerativeModel(
                    model_name,
                    generation_config={"response_mime_type": "application/json"}
                )
            else:
                model = genai.GenerativeModel(model_name)
            
            response = model.generate_content(prompt)
            return {"result": response.text}
        except Exception as e:
            print(f"Error performing text action {action}: {e}")
            return {"error": str(e)}
