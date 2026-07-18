import io
from pypdf import PdfReader

def extract_chunks_from_pdf(pdf_bytes: bytes, chunk_size: int = 800, chunk_overlap: int = 150) -> list[dict]:
    """
    Parses PDF bytes, extracts text page by page, and chunks the text.
    Returns a list of dictionaries with text content, page number, and chunk index.
    """
    pdf_file = io.BytesIO(pdf_bytes)
    reader = PdfReader(pdf_file)
    
    chunks = []
    chunk_index = 0
    
    for page_idx, page in enumerate(reader.pages):
        page_num = page_idx + 1
        text = page.extract_text()
        if not text:
            continue
            
        # Standard sliding window chunking per page (or across pages)
        # For simplicity, we chunk page-by-page. This helps identify the source page exactly.
        words = text.split()
        if not words:
            continue
            
        i = 0
        while i < len(words):
            # Take a chunk of words
            chunk_words = words[i : i + chunk_size]
            chunk_text = " ".join(chunk_words)
            
            chunks.append({
                "text": chunk_text,
                "page_number": page_num,
                "chunk_index": chunk_index
            })
            
            chunk_index += 1
            # Advance index by chunk_size - chunk_overlap
            i += (chunk_size - chunk_overlap)
            
            # If the remaining words are too few, stop
            if i + chunk_overlap >= len(words) and i < len(words):
                # Put the rest of the words in one last chunk if we aren't at the end
                last_words = words[i:]
                if len(last_words) > 5:  # only make a chunk if there's meaningful text
                    chunks.append({
                        "text": " ".join(last_words),
                        "page_number": page_num,
                        "chunk_index": chunk_index
                    })
                    chunk_index += 1
                break
                
    return chunks
