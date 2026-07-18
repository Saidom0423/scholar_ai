import os
import shutil
from abc import ABC, abstractmethod
import config

class StorageProvider(ABC):
    @abstractmethod
    def upload_file(self, file_data: bytes, filename: str) -> str:
        """Uploads a file and returns its path or URL."""
        pass

    @abstractmethod
    def download_file(self, file_path_or_url: str) -> bytes:
        """Downloads a file and returns its bytes."""
        pass

    @abstractmethod
    def delete_file(self, file_path_or_url: str) -> bool:
        """Deletes a file from storage."""
        pass

class LocalStorageProvider(StorageProvider):
    def __init__(self, upload_dir: str = config.UPLOAD_DIR):
        self.upload_dir = upload_dir
        if not os.path.exists(self.upload_dir):
            os.makedirs(self.upload_dir)

    def upload_file(self, file_data: bytes, filename: str) -> str:
        # Create a unique filename if necessary, here we assume it has been pre-processed
        file_path = os.path.join(self.upload_dir, filename)
        with open(file_path, "wb") as f:
            f.write(file_data)
        return file_path

    def download_file(self, file_path_or_url: str) -> bytes:
        if os.path.exists(file_path_or_url):
            with open(file_path_or_url, "rb") as f:
                return f.read()
        raise FileNotFoundError(f"File not found: {file_path_or_url}")

    def delete_file(self, file_path_or_url: str) -> bool:
        if os.path.exists(file_path_or_url):
            os.remove(file_path_or_url)
            return True
        return False

class SupabaseStorageProvider(StorageProvider):
    def __init__(self):
        # We import supabase inside init to avoid errors if the package is not loaded
        from supabase import create_client, Client
        self.url = config.SUPABASE_URL
        self.key = config.SUPABASE_KEY
        self.bucket = config.SUPABASE_BUCKET
        
        if not self.url or not self.key:
            raise ValueError("SUPABASE_URL and SUPABASE_KEY must be provided for Supabase storage mode.")
            
        self.client: Client = create_client(self.url, self.key)

    def upload_file(self, file_data: bytes, filename: str) -> str:
        # We upload to the storage bucket
        # Supabase API expects: path, file, file_options
        response = self.client.storage.from_(self.bucket).upload(
            path=filename,
            file=file_data,
            file_options={"content-type": "application/pdf", "x-upsert": "true"}
        )
        # Return the filename/path within the bucket
        return filename

    def download_file(self, file_path_or_url: str) -> bytes:
        # download returns bytes
        return self.client.storage.from_(self.bucket).download(file_path_or_url)

    def delete_file(self, file_path_or_url: str) -> bool:
        try:
            self.client.storage.from_(self.bucket).remove([file_path_or_url])
            return True
        except Exception:
            return False

# Export the active storage provider based on configuration
def get_storage_provider() -> StorageProvider:
    if config.STORAGE_TYPE == "supabase":
        return SupabaseStorageProvider()
    else:
        return LocalStorageProvider()
