import json
import re
import urllib.request
import urllib.error
import config

class AIService:
    def __init__(self):
        self.ollama_url = "http://localhost:11434"
        self.embedding_model = "all-minilm"
        self.llm_model = "qwen2.5:1.5b"

    def _call_ollama_generate(self, prompt: str, system_prompt: str = "You are a helpful study assistant AI.", response_json: bool = False) -> str:
        """Helper to call Ollama's /api/generate endpoint."""
        url = f"{self.ollama_url}/api/generate"
        payload = {
            "model": self.llm_model,
            "prompt": prompt,
            "system": system_prompt,
            "stream": False,
            "options": {
                "temperature": 0.7
            }
        }
        if response_json:
            payload["format"] = "json"
            
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req) as response:
                result = json.loads(response.read().decode())
                return result.get("response", "").strip()
        except urllib.error.URLError as e:
            print(f"Ollama connection error: {e}")
            raise Exception("Failed to communicate with local Ollama service. Please make sure Ollama is running.") from e

    def _call_ollama_embeddings(self, text: str) -> list[float]:
        """Helper to call Ollama's /api/embeddings endpoint."""
        url = f"{self.ollama_url}/api/embeddings"
        payload = {
            "model": self.embedding_model,
            "prompt": text
        }
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req) as response:
                result = json.loads(response.read().decode())
                return result.get("embedding", [])
        except urllib.error.URLError as e:
            print(f"Ollama connection error: {e}")
            raise Exception("Failed to communicate with local Ollama service. Please make sure Ollama is running.") from e

    def _extract_json(self, text: str):
        """Attempts to parse JSON, falling back to regex extraction of JSON markdown blocks or brackets."""
        # Try markdown code blocks first
        match = re.search(r"```json\s*(.*?)\s*```", text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(1).strip())
            except Exception:
                pass
        
        # Try brackets matching
        match = re.search(r"(\[.*\]|\{.*\})", text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(1).strip())
            except Exception:
                pass
                
        # Raw parse fallback
        try:
            return json.loads(text.strip())
        except Exception as e:
            print(f"Failed to parse JSON: {text}. Error: {e}")
            raise e

    def get_embedding(self, text: str, is_query: bool = False) -> list[float]:
        """Generates a vector embedding for the input text locally using Ollama."""
        return self._call_ollama_embeddings(text)

    def get_embeddings_batch(self, texts: list[str]) -> list[list[float]]:
        """Generates vector embeddings for a list of texts locally in batch using Ollama."""
        embeddings = []
        for text in texts:
            embeddings.append(self._call_ollama_embeddings(text))
        return embeddings

    def generate_summary(self, document_title: str, document_text_sample: str) -> str:
        """Generates a study summary of a document based on text samples locally."""
        prompt = f"""Write a comprehensive, well-structured study guide and summary for the document: "{document_title}".

Based on this text excerpt from the document:
---
{document_text_sample[:12000]}
---

Your study guide should include:
1. **Overview & Main Themes**: A high-level description of what the document covers.
2. **Key Concepts & Definitions**: Bullet points explaining crucial terms or equations.
3. **Core Insights / Takeaways**: Central arguments or points.
4. **Study Tips / Review Questions**: Recommendations on how to study this material.

Use clear markdown headings, bold text, and bullet points. Make it structured and easy to read."""
        
        return self._call_ollama_generate(prompt)

    def generate_flashcards(self, document_text_sample: str) -> list[dict]:
        """Generates a list of flashcards (question and answer pairs) from document text locally."""
        prompt = f"""Based on the following document text, generate 8 to 12 high-quality, conceptual flashcards for a student to study.
The questions should test understanding of key concepts, definitions, or equations. The answers should be concise but informative.

Return ONLY a JSON array of flashcards, where each object has exactly two keys: "question" and "answer". Do not include any explanation or markdown formatting other than raw JSON.

Text Excerpt:
---
{document_text_sample[:10000]}
---"""
        try:
            raw_response = self._call_ollama_generate(
                prompt, 
                system_prompt="You are a JSON generator. You only respond with JSON arrays containing objects with 'question' and 'answer' keys.",
                response_json=True
            )
            flashcards = self._extract_json(raw_response)
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
        """Answers a user's question relative to retrieved document chunks (RAG) locally."""
        context_str = ""
        for chunk in retrieved_chunks:
            doc_title = chunk.get("document_title", "Unknown Document")
            context_str += f"[Source: \"{doc_title}\", Page {chunk['page_number']}]:\n{chunk['text']}\n\n"

        history_str = ""
        if chat_history:
            for msg in chat_history[-6:]:
                role = "User" if msg["sender"] == "user" else "Assistant"
                history_str += f"{role}: {msg['text']}\n"

        prompt = f"""Answer the user's question using the provided document context below. If the answer is not in the context, use your general knowledge, but clearly state that it is not explicitly mentioned in the documents.
Cite both the document title and page number when giving information from the context.

Document Context:
---
{context_str}
---

Recent Chat History:
{history_str}
User's Question: {question}

Provide a helpful, precise, and friendly answer. Cite the specific book and page number in brackets like ["Biology Textbook", Page 3] when referring to information."""
        
        return self._call_ollama_generate(prompt)

    def perform_text_action(self, text: str, action: str, target_language: str = "Spanish") -> dict:
        """Performs an AI text action (explain, summarize, generate_flashcards, generate_quiz, translate) locally."""
        if action == "explain":
            prompt = f"""Explain the following text snippet in detail. Use simple, clear language. Use markdown headings, bullet points, and bold text to structure your response.

Text:
---
{text}
---"""
            result = self._call_ollama_generate(prompt)
            return {"result": result}

        elif action == "summarize":
            prompt = f"""Provide a highly concise bulleted summary of the following text snippet. Focus only on the key facts, terms, or concepts.

Text:
---
{text}
---"""
            result = self._call_ollama_generate(prompt)
            return {"result": result}

        elif action == "translate":
            prompt = f"""Translate the following text into {target_language}. Keep the tone and formatting natural. Return ONLY the translated text, do not add any comments or headers.

Text:
---
{text}
---"""
            result = self._call_ollama_generate(prompt)
            return {"result": result}

        elif action == "generate_flashcards":
            prompt = f"""Based on the following text snippet, generate 3 to 5 high-quality conceptual flashcards.
Return ONLY a JSON array of flashcards, where each object has exactly two keys: "question" and "answer". Do not include any explanation or markdown formatting other than raw JSON.

Text:
---
{text}
---"""
            try:
                raw_response = self._call_ollama_generate(
                    prompt,
                    system_prompt="You are a JSON generator. Respond only with a JSON array of objects with keys 'question' and 'answer'.",
                    response_json=True
                )
                parsed = self._extract_json(raw_response)
                return {"result": json.dumps(parsed)}
            except Exception as e:
                return {"error": str(e)}

        elif action == "generate_quiz":
            prompt = f"""Based on the following text snippet, generate 3 to 5 multiple-choice questions for a student quiz.
Return ONLY a JSON array of questions, where each object has exactly three keys:
1. "question": The question text.
2. "options": An array of exactly 4 choices/options.
3. "correct_answer": The exact string of the correct choice from the options array.

Do not include any explanation or markdown formatting other than raw JSON.

Text:
---
{text}
---"""
            try:
                raw_response = self._call_ollama_generate(
                    prompt,
                    system_prompt="You are a JSON generator. Respond only with a JSON array of quiz question objects.",
                    response_json=True
                )
                parsed = self._extract_json(raw_response)
                return {"result": json.dumps(parsed)}
            except Exception as e:
                return {"error": str(e)}

        else:
            return {"error": f"Invalid action: {action}"}
