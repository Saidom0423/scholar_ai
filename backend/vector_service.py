import json
import math
from database import SessionLocal
import models

class VectorService:
    def __init__(self):
        # No external server initialization needed. Vector storage is backed by SQLAlchemy.
        pass

    def upsert_chunks(self, chunks: list[dict], embeddings: list[list[float]], user_id: int, document_id: int):
        """
        Saves document chunks and their embeddings (as JSON text) into the SQL database.
        """
        db = SessionLocal()
        try:
            for chunk, vector in zip(chunks, embeddings):
                db_chunk = models.DocumentChunk(
                    document_id=document_id,
                    page_number=chunk["page_number"],
                    chunk_index=chunk["chunk_index"],
                    text=chunk["text"],
                    embedding=json.dumps(vector)
                )
                db.add(db_chunk)
            db.commit()
        except Exception as e:
            db.rollback()
            raise e
        finally:
            db.close()

    def search_similar_chunks(
        self, 
        query_vector: list[float], 
        user_id: int, 
        document_id: int = None, 
        document_ids: list[int] = None,
        top_k: int = 5
    ) -> list[dict]:
        """
        Calculates cosine similarity in Python over all chunks matching the document constraints.
        Returns the top_k most similar chunks, including parent document title.
        """
        db = SessionLocal()
        try:
            # Query chunks joined with Document to ensure user ownership
            query = db.query(models.DocumentChunk).join(models.Document).filter(
                models.Document.user_id == user_id
            )
            
            if document_id is not None:
                query = query.filter(models.DocumentChunk.document_id == document_id)
            elif document_ids is not None and len(document_ids) > 0:
                query = query.filter(models.DocumentChunk.document_id.in_(document_ids))
                
            chunks = query.all()
            
            scored_chunks = []
            for chunk in chunks:
                chunk_vector = json.loads(chunk.embedding)
                similarity = self._cosine_similarity(query_vector, chunk_vector)
                scored_chunks.append({
                    "text": chunk.text,
                    "page_number": chunk.page_number,
                    "document_title": chunk.document.title,
                    "document_id": chunk.document_id,
                    "score": similarity
                })
                
            # Sort chunks by similarity score descending
            scored_chunks.sort(key=lambda x: x["score"], reverse=True)
            return scored_chunks[:top_k]
        finally:
            db.close()

    def delete_document_vectors(self, user_id: int, document_id: int):
        """
        Clean up function. Handled by SQLAlchemy cascade delete, 
        but kept for API compatibility with main.py router.
        """
        db = SessionLocal()
        try:
            db.query(models.DocumentChunk).filter(
                models.DocumentChunk.document_id == document_id
            ).delete()
            db.commit()
        except Exception:
            db.rollback()
        finally:
            db.close()

    def _cosine_similarity(self, v1: list[float], v2: list[float]) -> float:
        """Helper to calculate cosine similarity between two float vectors."""
        dot_product = sum(a * b for a, b in zip(v1, v2))
        magnitude_v1 = math.sqrt(sum(a * a for a in v1))
        magnitude_v2 = math.sqrt(sum(a * a for a in v2))
        
        if magnitude_v1 * magnitude_v2 == 0:
            return 0.0
            
        return dot_product / (magnitude_v1 * magnitude_v2)
