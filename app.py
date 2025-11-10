from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from routes import conversation, websocket, health, subagent

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://ey-ios.com"],  
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"],  
)

app.include_router(conversation.router)
app.include_router(websocket.router)
app.include_router(health.router)
app.include_router(subagent.router)

@app.get("/")
async def get():
    with open('index.html', 'r', encoding='utf-8') as f:
        html_content = f.read()
    return HTMLResponse(content=html_content)