FROM python:3.11.14-slim
RUN groupadd -r pyron && useradd -r -g pyron pyron
COPY . app/
RUN chown -R pyron:pyron app/
RUN pip install -r app/requirements.txt
USER pyron
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]