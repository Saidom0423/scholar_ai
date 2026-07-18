import sys
# Python 3.14 Protobuf metaclass compatibility patch
sys.modules['google._upb._message'] = None
sys.modules['google._upb'] = None

import os
from typing import List, Optional
from fastapi import FastAPI, Depends, HTTPException, status, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from datetime import datetime

import config
import models
from database import engine, get_db
from auth import get_password_hash, verify_password, create_access_token, get_current_user
from storage import get_storage_provider
from pdf_service import extract_chunks_from_pdf
from vector_service import VectorService
from ai_service import AIService

# Create SQL Tables on startup (if SQLite, this creates files; if Postgres, it creates tables)
models.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="AI Study Assistant API",
    description="Backend API for PDF studying, vector RAG search, summaries, and flashcards",
    version="1.0.0"
)

# Enable CORS for frontend API calls
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Services
storage_provider = get_storage_provider()
vector_service = VectorService()
ai_service = AIService()


# --- Pydantic Schemas ---

class UserRegister(BaseModel):
    email: str = Field(..., description="Email address")
    phone: Optional[str] = Field(None, description="Phone number")
    password: str = Field(..., min_length=4)

class UserResponse(BaseModel):
    id: int
    email: str
    phone: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str

class DocumentResponse(BaseModel):
    id: int
    title: str
    upload_date: datetime

    class Config:
        from_attributes = True

class ChatQuery(BaseModel):
    question: str

class LibraryChatQuery(BaseModel):
    question: str
    document_ids: Optional[List[int]] = None

class ChatResponse(BaseModel):
    answer: str

class ChatMessageResponse(BaseModel):
    id: int
    sender: str
    text: str
    timestamp: datetime

    class Config:
        from_attributes = True

class FlashcardResponse(BaseModel):
    id: int
    question: str
    answer: str

    class Config:
        from_attributes = True

class FlashcardSetResponse(BaseModel):
    id: int
    title: str
    created_at: datetime
    flashcards: List[FlashcardResponse] = []

    class Config:
        from_attributes = True


class TextActionQuery(BaseModel):
    text: str
    action: str  # "explain", "summarize", "generate_flashcards", "generate_quiz", "translate"
    target_language: Optional[str] = "Spanish"

class TextActionResponse(BaseModel):
    action: str
    result: str

class FlashcardItem(BaseModel):
    question: str
    answer: str

class FlashcardBatchSave(BaseModel):
    title: str
    flashcards: List[FlashcardItem]


# --- Authentication Endpoints ---

@app.post("/api/auth/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(user_in: UserRegister, db: Session = Depends(get_db)):
    email_clean = user_in.email.strip().lower()
    phone_clean = user_in.phone.strip() if user_in.phone else None
    
    # Check if email is already taken
    existing_email = db.query(models.User).filter(models.User.email == email_clean).first()
    if existing_email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email address already registered"
        )
        
    # Check if phone is already taken (if provided)
    if phone_clean:
        existing_phone = db.query(models.User).filter(models.User.phone == phone_clean).first()
        if existing_phone:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Phone number already registered"
            )
    
    hashed_pwd = get_password_hash(user_in.password)
    db_user = models.User(email=email_clean, phone=phone_clean, hashed_password=hashed_pwd)
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@app.post("/api/auth/login", response_model=Token)
def login(username: str = Form(...), password: str = Form(...), db: Session = Depends(get_db)):
    # The standard 'username' parameter handles either email or phone input
    clean_identifier = username.strip()
    user = db.query(models.User).filter(
        (models.User.email == clean_identifier.lower()) | (models.User.phone == clean_identifier)
    ).first()
    
    if not user or not verify_password(password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email/phone or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Store email as subject in access token
    access_token = create_access_token(data={"sub": user.email})
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/api/auth/me", response_model=UserResponse)
def get_me(current_user: models.User = Depends(get_current_user)):
    return current_user


# --- Document Endpoints ---

@app.post("/api/documents/upload", response_model=DocumentResponse)
async def upload_document(
    file: UploadFile = File(...),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only PDF documents are supported."
        )
        
    pdf_bytes = await file.read()
    
    # 1. Parse and chunk the PDF text
    try:
        chunks = extract_chunks_from_pdf(pdf_bytes)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to parse PDF file: {str(e)}"
        )
        
    if not chunks:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="The PDF has no extractable text."
        )
        
    # Create DB entry first to get the document ID
    db_doc = models.Document(
        user_id=current_user.id,
        title=file.filename,
        file_path=""  # Updated below
    )
    db.add(db_doc)
    db.commit()
    db.refresh(db_doc)
    
    # 2. Upload file bytes to Storage Provider (Local or Supabase)
    unique_filename = f"user_{current_user.id}_doc_{db_doc.id}.pdf"
    try:
        storage_path = storage_provider.upload_file(pdf_bytes, unique_filename)
        db_doc.file_path = storage_path
        db.commit()
    except Exception as e:
        db.delete(db_doc)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to store PDF file: {str(e)}"
        )

    # 3. Generate embeddings & Upsert to Vector DB (Qdrant)
    try:
        # Extract text chunks
        chunk_texts = [c["text"] for c in chunks]
        embeddings = ai_service.get_embeddings_batch(chunk_texts)
        
        # Upsert chunks and vectors into Qdrant
        vector_service.upsert_chunks(
            chunks=chunks,
            embeddings=embeddings,
            user_id=current_user.id,
            document_id=db_doc.id
        )
    except Exception as e:
        # Cleanup file if vector indexing fails
        storage_provider.delete_file(db_doc.file_path)
        db.delete(db_doc)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to index PDF content: {str(e)}"
        )
        
    return db_doc

@app.get("/api/documents", response_model=List[DocumentResponse])
def get_documents(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    return db.query(models.Document).filter(models.Document.user_id == current_user.id).all()

@app.get("/api/documents/{doc_id}/download")
def download_document(
    doc_id: int, 
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    doc = db.query(models.Document).filter(
        models.Document.id == doc_id, 
        models.Document.user_id == current_user.id
    ).first()
    
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
        
    try:
        file_bytes = storage_provider.download_file(doc.file_path)
        return StreamingResponse(
            io_bytes_stream := io_bytes_wrapper(file_bytes),
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={doc.title}"}
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
            detail=f"Failed to read file: {str(e)}"
        )

# Helper function for streaming file bytes
def io_bytes_wrapper(data: bytes):
    import io
    yield from io.BytesIO(data)

@app.delete("/api/documents/{doc_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_document(
    doc_id: int, 
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    doc = db.query(models.Document).filter(
        models.Document.id == doc_id, 
        models.Document.user_id == current_user.id
    ).first()
    
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
        
    # 1. Delete from storage
    storage_provider.delete_file(doc.file_path)
    
    # 2. Delete from vector store
    vector_service.delete_document_vectors(user_id=current_user.id, document_id=doc.id)
    
    # 3. Delete from DB (cascading deletes chat messages & flashcards)
    db.delete(doc)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- AI Chat / Study Endpoints ---

@app.post("/api/documents/{doc_id}/chat", response_model=ChatMessageResponse)
def chat_with_document(
    doc_id: int,
    query: ChatQuery,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Verify document ownership
    doc = db.query(models.Document).filter(
        models.Document.id == doc_id, 
        models.Document.user_id == current_user.id
    ).first()
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")

    # 1. Embed query
    try:
        query_vector = ai_service.get_embedding(query.question, is_query=True)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process query embeddings: {str(e)}"
        )

    # 2. Retrieve relevant chunks from Qdrant
    retrieved_chunks = vector_service.search_similar_chunks(
        query_vector=query_vector,
        user_id=current_user.id,
        document_id=doc_id,
        top_k=5
    )

    # 3. Retrieve recent chat history
    history_msgs = db.query(models.ChatMessage).filter(
        models.ChatMessage.document_id == doc_id,
        models.ChatMessage.user_id == current_user.id
    ).order_by(models.ChatMessage.timestamp.asc()).all()
    
    chat_history = [{"sender": msg.sender, "text": msg.text} for msg in history_msgs]

    # 4. Ask Gemini
    answer_text = ai_service.answer_question_with_context(
        question=query.question,
        retrieved_chunks=retrieved_chunks,
        chat_history=chat_history
    )

    # 5. Store user and assistant messages in database
    user_msg = models.ChatMessage(
        user_id=current_user.id,
        document_id=doc_id,
        sender="user",
        text=query.question
    )
    assistant_msg = models.ChatMessage(
        user_id=current_user.id,
        document_id=doc_id,
        sender="assistant",
        text=answer_text
    )
    db.add(user_msg)
    db.add(assistant_msg)
    db.commit()
    db.refresh(assistant_msg)

    return assistant_msg

@app.get("/api/documents/{doc_id}/chat-history", response_model=List[ChatMessageResponse])
def get_chat_history(
    doc_id: int, 
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # Verify document ownership
    doc = db.query(models.Document).filter(
        models.Document.id == doc_id, 
        models.Document.user_id == current_user.id
    ).first()
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
        
    return db.query(models.ChatMessage).filter(
        models.ChatMessage.document_id == doc_id,
        models.ChatMessage.user_id == current_user.id
    ).order_by(models.ChatMessage.timestamp.asc()).all()


@app.post("/api/documents/text-action", response_model=TextActionResponse)
def perform_text_action(
    query: TextActionQuery,
    current_user: models.User = Depends(get_current_user)
):
    """Endpoint to run AI actions on selected text (explain, summarize, quiz, translation, flashcards)"""
    res = ai_service.perform_text_action(
        text=query.text,
        action=query.action,
        target_language=query.target_language
    )
    if "error" in res:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=res["error"]
        )
    return {"action": query.action, "result": res["result"]}


@app.post("/api/documents/{doc_id}/flashcards/save-batch", response_model=FlashcardSetResponse)
def save_flashcard_batch(
    doc_id: int,
    batch: FlashcardBatchSave,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Endpoint to save a generated batch of flashcards into a new set associated with a document"""
    # Verify document ownership
    doc = db.query(models.Document).filter(
        models.Document.id == doc_id, 
        models.Document.user_id == current_user.id
    ).first()
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
        
    try:
        # Create FlashcardSet
        flashcard_set = models.FlashcardSet(
            user_id=current_user.id,
            document_id=doc_id,
            title=batch.title if batch.title.strip() else f"Flashcards for {doc.title}"
        )
        db.add(flashcard_set)
        db.commit()
        db.refresh(flashcard_set)
        
        # Create Flashcard items
        for card in batch.flashcards:
            db_card = models.Flashcard(
                set_id=flashcard_set.id,
                question=card.question,
                answer=card.answer
            )
            db.add(db_card)
        db.commit()
        
        db.refresh(flashcard_set)
        return flashcard_set
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save batch flashcards: {str(e)}"
        )


@app.post("/api/documents/{doc_id}/summary", response_model=ChatResponse)
def get_document_summary(
    doc_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Verify document ownership
    doc = db.query(models.Document).filter(
        models.Document.id == doc_id, 
        models.Document.user_id == current_user.id
    ).first()
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
        
    try:
        # Download document to extract text sample
        file_bytes = storage_provider.download_file(doc.file_path)
        chunks = extract_chunks_from_pdf(file_bytes)
        
        # Take the first 8 chunks of the document to represent a substantial sample
        sample_chunks = chunks[:8]
        sample_text = "\n\n".join([c["text"] for c in sample_chunks])
        
        summary = ai_service.generate_summary(doc.title, sample_text)
        return {"answer": summary}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate summary: {str(e)}"
        )

@app.post("/api/documents/{doc_id}/flashcards", response_model=FlashcardSetResponse)
def create_flashcard_set(
    doc_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Verify document ownership
    doc = db.query(models.Document).filter(
        models.Document.id == doc_id, 
        models.Document.user_id == current_user.id
    ).first()
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
        
    try:
        # Download document and extract sample text
        file_bytes = storage_provider.download_file(doc.file_path)
        chunks = extract_chunks_from_pdf(file_bytes)
        
        # Take sample chunks
        sample_chunks = chunks[:8]
        sample_text = "\n\n".join([c["text"] for c in sample_chunks])
        
        # Generate flashcard cards using AI
        cards_data = ai_service.generate_flashcards(sample_text)
        if not cards_data:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="AI failed to generate flashcards from text."
            )
            
        # Create FlashcardSet
        flashcard_set = models.FlashcardSet(
            user_id=current_user.id,
            document_id=doc_id,
            title=f"Flashcards for {doc.title}"
        )
        db.add(flashcard_set)
        db.commit()
        db.refresh(flashcard_set)
        
        # Create Flashcard items
        for card in cards_data:
            db_card = models.Flashcard(
                set_id=flashcard_set.id,
                question=card["question"],
                answer=card["answer"]
            )
            db.add(db_card)
        db.commit()
        
        db.refresh(flashcard_set)
        return flashcard_set
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create flashcards: {str(e)}"
        )

@app.get("/api/documents/{doc_id}/flashcard-sets", response_model=List[FlashcardSetResponse])
def get_flashcard_sets(
    doc_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Verify document ownership
    doc = db.query(models.Document).filter(
        models.Document.id == doc_id, 
        models.Document.user_id == current_user.id
    ).first()
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Document not found")
        
    return db.query(models.FlashcardSet).filter(
        models.FlashcardSet.document_id == doc_id,
        models.FlashcardSet.user_id == current_user.id
    ).all()

@app.get("/api/flashcard-sets/{set_id}", response_model=FlashcardSetResponse)
def get_flashcard_set(
    set_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    fset = db.query(models.FlashcardSet).filter(
        models.FlashcardSet.id == set_id,
        models.FlashcardSet.user_id == current_user.id
    ).first()
    if not fset:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Flashcard set not found")
    return fset

@app.post("/api/library/chat", response_model=ChatMessageResponse)
def library_chat(
    query: LibraryChatQuery,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # If specific documents are selected, verify ownership of each
    if query.document_ids:
        for doc_id in query.document_ids:
            doc = db.query(models.Document).filter(
                models.Document.id == doc_id,
                models.Document.user_id == current_user.id
            ).first()
            if not doc:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Unauthorized access to document {doc_id} or document does not exist."
                )

    # 1. Generate query embedding
    try:
        query_vector = ai_service.get_embedding(query.question, is_query=True)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate search embeddings: {str(e)}"
        )

    # 2. Search library chunks
    retrieved_chunks = vector_service.search_similar_chunks(
        query_vector=query_vector,
        user_id=current_user.id,
        document_ids=query.document_ids,
        top_k=7  # Pull slightly more context for cross-book queries
    )

    # 3. Retrieve recent library chat history (document_id is None)
    history_msgs = db.query(models.ChatMessage).filter(
        models.ChatMessage.document_id == None,
        models.ChatMessage.user_id == current_user.id
    ).order_by(models.ChatMessage.timestamp.asc()).all()

    chat_history = [{"sender": msg.sender, "text": msg.text} for msg in history_msgs]

    # 4. Generate answer
    answer_text = ai_service.answer_question_with_context(
        question=query.question,
        retrieved_chunks=retrieved_chunks,
        chat_history=chat_history
    )

    # 5. Store message history in DB (with document_id = None)
    user_msg = models.ChatMessage(
        user_id=current_user.id,
        document_id=None,
        sender="user",
        text=query.question
    )
    assistant_msg = models.ChatMessage(
        user_id=current_user.id,
        document_id=None,
        sender="assistant",
        text=answer_text
    )
    db.add(user_msg)
    db.add(assistant_msg)
    db.commit()
    db.refresh(assistant_msg)

    return assistant_msg

@app.get("/api/library/chat-history", response_model=List[ChatMessageResponse])
def get_library_chat_history(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return db.query(models.ChatMessage).filter(
        models.ChatMessage.document_id == None,
        models.ChatMessage.user_id == current_user.id
    ).order_by(models.ChatMessage.timestamp.asc()).all()
