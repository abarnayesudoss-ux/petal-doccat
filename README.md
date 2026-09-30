# Petal — RAG Document Chatbot

Upload PDFs, PowerPoints, Word files and text files, then ask questions in plain English. Petal finds the relevant passages in **all** your documents and answers with **Google Gemini**, showing sources like `research.pdf — Page 15` or `deck.pptx — Slide 8`.

- **One secret only:** `GEMINI_API_KEY`. No OpenAI, Pinecone, Hugging Face or any other key.
- **FastAPI** backend, plain **HTML/CSS/JavaScript** frontend (no Streamlit, no Gradio), **Gunicorn + Uvicorn** in production.
- Ready for **GitHub Desktop** and **Render**.

---

## 1. Features

- Drag-and-drop upload of many files at once: PDF, PPT, PPTX, DOC, DOCX, TXT (default limit 100 MB per file).
- Progress states: *Uploading… → Processing document… → Document ready ✓*. The UI never freezes.
- Answers grounded in your files only. If the answer isn't there: *"I couldn't find this information in the uploaded documents."*
- Handles what/why/how/when/where/who, explain, summarize, list, compare, definition and multi-part questions.
- Follow-up questions work ("What technologies does **it** use?") thanks to chat memory.
- Sources with page or slide numbers, only when they really exist.
- Scanned PDFs: pages without text are read with Gemini vision (OCR fallback, same key).
- Duplicate detection, file-type checks, safe filenames, friendly error messages (no stack traces).
- Each browser gets its own private workspace, so visitors on a deployed site never see each other's files.
- Responsive pink interface for desktop, tablet and phone.

## 2. Architecture

```
Upload → validate (type, size, magic bytes, duplicate)
       → extract text (page/slide aware)
       → clean → chunk (never crosses a page/slide)
       → embed with Gemini (gemini-embedding-001)
       → store vectors (NumPy, cosine similarity)

Question → (rewrite follow-ups into a standalone question)
         → embed → similarity search + keyword boost
         → top passages (from every document)
         → Gemini writes a grounded answer → sources shown
```

| Part | Choice |
|---|---|
| LLM | Gemini (`gemini-2.5-flash`, with automatic fallback names) |
| Embeddings | `gemini-embedding-001`, same key |
| Vector store | Simple NumPy cosine search saved under `data/` (no FAISS/Chroma install, no server, no key) |
| PDF | PyMuPDF (text in reading order, tables, page numbers) |
| PPTX | python-pptx (titles, bullets, tables, speaker notes, slide numbers) |
| DOCX | python-docx (headings, paragraphs, tables) |
| DOC / PPT | Best effort, see *Troubleshooting* |

## 3. Folder structure

```
petal-docchat/
├── backend/
│   ├── main.py                 FastAPI app (serves the frontend too)
│   ├── config.py               settings, reads GEMINI_API_KEY
│   ├── routes/                 /upload /documents /chat
│   ├── services/               gemini.py, ingest.py, chat.py
│   ├── rag/                    chunker.py, store.py, retriever.py
│   ├── document_processors/    pdf, pptx, docx, txt, legacy doc/ppt
│   └── utils/
├── frontend/                   index.html, style.css, app.js
├── uploads/                    temporary files (git-ignored)
├── data/                       vector stores (git-ignored)
├── .env.example
├── .gitignore
├── requirements.txt
├── render.yaml
├── start.sh
└── README.md
```

## 4. Run locally

You need **Python 3.11 or 3.12** and a free Gemini API key from <https://aistudio.google.com/apikey>.

**Windows (PowerShell)**

```powershell
cd petal-docchat
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
notepad .env
```

**macOS / Linux**

```bash
cd petal-docchat
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
nano .env
```

In `.env`, replace the placeholder so the file contains exactly one line:

```
GEMINI_API_KEY=your_real_key_here
```

Start the app:

```bash
uvicorn backend.main:app --reload
```

Open <http://127.0.0.1:8000>. The frontend is served by the same app, so there is nothing else to start.
(On macOS/Linux you can also run `./start.sh`, which uses the same Gunicorn command as Render.)

## 5. Put the project on GitHub with GitHub Desktop

1. Extract the ZIP.
2. Open **GitHub Desktop** and sign in.
3. Choose **File → Add local repository…** and select the extracted `petal-docchat` folder.
4. If it says the folder is not a repository, click **create a repository**, then **Create repository**.
5. Check the changed-files list: `.env` must **not** appear (it is git-ignored). Only `.env.example` should be there.
6. Type a summary such as `Initial commit` and click **Commit to main**.
7. Click **Publish repository**. Untick **Keep this code private** only if you want it public.

## 6. Deploy on Render

1. Sign in at <https://render.com> and connect your GitHub account.
2. Click **New + → Blueprint** and pick your repository (Render reads `render.yaml`). Or choose **New + → Web Service** and fill the fields manually:
   - **Runtime:** Python 3
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:**
     ```
     gunicorn backend.main:app -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT --workers 1 --timeout 180
     ```
   - **Health Check Path:** `/health`
3. Under **Environment**, add the only secret:

   | Key | Value |
   |---|---|
   | `GEMINI_API_KEY` | your Gemini API key |

   (`render.yaml` also sets `PYTHON_VERSION=3.12.3`; you don't type that.)
4. Click **Deploy**. When it is live, open `https://<your-service>.onrender.com/health`. You should see `{"status":"ok"}`.

**Why `--workers 1`?** Each worker keeps its own in-memory index. One worker (plus threads) keeps every request looking at the same documents.

### Persistence on Render (please read)

Render's free web services have an **ephemeral disk**: uploaded documents and their index are lost when the service restarts, redeploys, or wakes from sleep (free services sleep after inactivity). Users simply upload their files again. Keeping data permanently would need a paid persistent disk (mounted at `data/`) or an external database, which this project deliberately avoids. Workspaces are also deleted after 24 hours of inactivity.

## 7. Supported files

PDF • PPT • PPTX • DOC • DOCX • TXT

## 8. How the RAG part works

1. **Extract** – text is read per page (PDF) or per slide (PPTX) so locations stay correct.
2. **Chunk** – text is split into ~1,200-character passages with a small overlap. A passage never spans two pages or slides.
3. **Embed** – each passage becomes a vector with Gemini embeddings and is stored with its source.
4. **Retrieve** – your question is embedded and compared with every passage (cosine similarity plus a small keyword boost, so exact terms like "Project Name" rank well). With several documents, each contributes its best passages. For "summarize this document" questions, passages are sampled evenly across the whole file.
5. **Answer** – Gemini receives only the retrieved passages and must answer from them, or say it can't find the answer.

## 9. Troubleshooting

| Problem | Fix |
|---|---|
| Yellow banner "API key is missing" | `.env` must be in the project root, contain `GEMINI_API_KEY=...`, and the server must be restarted. On Render, add it under Environment and redeploy. |
| "The Gemini API key was rejected" | Copy the key again from Google AI Studio, no quotes or spaces. |
| "too many requests" / slow processing of big files | The free Gemini tier limits embedding requests per minute. Petal retries automatically; very large documents can take several minutes. |
| PDF says "No readable text" | It is probably a scan. Scanned pages are read with Gemini vision automatically (first 80 pages); retry with a clearer copy if it still fails. |
| `.doc` / `.ppt` looks incomplete | These old binary formats are read best-effort (fully converted if LibreOffice is installed). Re-save as `.docx` / `.pptx` for the best result. |
| "password-protected" | Remove the password and upload again. |
| Documents disappeared on Render | Expected on the free plan, see *Persistence*. |
| `pip install` fails on Python 3.13+ | Use Python 3.12 (`.python-version` is provided for Render). |
| Port already in use locally | `uvicorn backend.main:app --reload --port 8001` |

Optional settings (all have defaults, none are required): `MAX_UPLOAD_MB`, `MAX_FILES_PER_SESSION`, `OCR_MAX_PAGES`, `SESSION_TTL_HOURS`.

## 10. Security notes

The API key is read only by the backend from the environment, is never sent to the browser, and is never logged. Uploaded filenames are sanitised, file types and signatures are checked, temporary files are deleted after processing, and errors returned to users are friendly messages without stack traces.
