# ScholarAI - Intelligent Study Assistant

ScholarAI is a premium, feature-rich study workspace designed to help students learn, summarize, study, and test themselves on their study material. By integrating advanced AI models (Gemini) with interactive PDF reading tools, ScholarAI provides a highly interactive pair-learning environment.

## Key Features

- **📂 Document Library**: Upload, manage, and delete study documents (PDFs up to 20MB).
- **📖 Interactive PDF Reader**: Responsive split-pane layout to read PDFs while chatting with the AI.
- **✨ Highlight & Ask Context Menu**: Select any text snippet inside the PDF reader to trigger a custom glassmorphism context menu offering:
  - 📖 **Explain**: Detailed, structured explanations using Gemini.
  - 📝 **Summarize**: Highly concise bulleted key concepts.
  - 🎴 **Generate Flashcards**: Creates study cards with the option to save them into decks.
  - ❓ **Generate Quiz**: Practice multiple-choice questions with real-time scoring.
  - 🌐 **Translate**: Instant translation into 10+ target languages.
- **💬 AI Chat Assistant**: Inline document discussion and contextual question-answering with automated citations.
- **⚡ Automatic Summaries**: Generate an instant overview, key definitions, and bulleted study guides.
- **🎴 Flashcard Decks**: Turn complex concepts into interactive decks for spaced repetition studies.

---

## Tech Stack

### Frontend
- **Framework**: Flutter (Web, Desktop, and Mobile support)
- **State Management**: Flutter Riverpod
- **Routing**: GoRouter
- **PDF Rendering**: Syncfusion Flutter PDF Viewer

### Backend
- **Framework**: FastAPI (Python)
- **Database**: SQLite with SQLAlchemy ORM
- **Authentication**: JWT authentication with SHA-256 password hashing
- **AI Models**: Google Gemini (`gemini-flash-latest`)
- **PDF Extraction**: PyPDF

---

## Setup & Running Guide

### 1. Prerequisites
- **Flutter SDK**: Ensure Flutter is installed and configured on your system.
- **Python 3.10+**: Ensure Python is installed.

### 2. Backend Setup
1. Open a terminal in the `backend/` directory.
2. Initialize and activate a virtual environment:
   ```bash
   python -m venv venv
   # On Windows:
   venv\Scripts\activate
   # On macOS/Linux:
   source venv/bin/activate
   ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. Create a `.env` file in the `backend/` directory using `.env.example` as a template, and fill in your `GEMINI_API_KEY`:
   ```env
   ENV=local
   JWT_SECRET=your-secure-secret-key
   ACCESS_TOKEN_EXPIRE_MINUTES=1440
   GEMINI_API_KEY=your_gemini_api_key_here
   ```
5. Run the backend server:
   ```bash
   uvicorn main:app --reload
   ```
   The backend will be running at `http://127.0.0.1:8000`.

### 3. Frontend Setup
1. Open a terminal in the `frontend/` directory.
2. Fetch Flutter package dependencies:
   ```bash
   flutter pub get
   ```
3. Run the development server (web target):
   ```bash
   flutter run -d chrome --web-port=3000
   ```
   The application will launch in Chrome at `http://localhost:3000`.

---

## Git Operations

To push latest changes to remote:
```bash
git add .
git commit -m "Add root README.md documentation"
git push https://github.com/Saidom0423/scholar_ai.git master
```
