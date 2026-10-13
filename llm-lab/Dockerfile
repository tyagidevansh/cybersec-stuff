FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY system_prompt.txt .
COPY inbox.json .
COPY docs/ docs/
COPY templates/ templates/
COPY static/ static/
ENV PORT=6000 SECURE=0
EXPOSE 6000
CMD ["python", "app.py"]
