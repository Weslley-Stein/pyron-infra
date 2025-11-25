# Pyron Infra

This repository contains the infrastructure and application code for **Pyron**, a trading signal processing system. It includes Terraform configurations for provisioning resources on DigitalOcean and a FastAPI application for handling signals.

## Architecture

The system consists of the following components:

-   **Infrastructure**: Provisioned via Terraform on DigitalOcean.
-   **Application**: A Dockerized stack running on a DigitalOcean Droplet.
    -   **API**: FastAPI service that receives webhooks/signals.
    -   **Worker**: Background worker that processes signals from a queue.
    -   **Redis**: Message broker for the signal queue.
    -   **MongoDB**: Database for storing processed signals.

## Infrastructure

The infrastructure is managed using **Terraform** and includes:

-   **DigitalOcean Droplet**: Ubuntu 24.04 server hosting the application.
    -   Provisioned with `cloud-init` to automatically install Docker, Nginx, and Certbot.
-   **Firewall**: Restricts access to essential ports:
    -   `22` (SSH)
    -   `80` (HTTP)
    -   `443` (HTTPS)
-   **Container Registry**: Stores the Docker images for the API and Worker.
-   **Terraform Backend**: State is stored in a DigitalOcean Space (S3-compatible) for collaboration and safety.

### Cloud-init
The `infra/cloud-init.yaml` file configures the Droplet upon creation, ensuring that:
-   System packages are updated and upgraded.
-   **Docker**, **Nginx**, and **Certbot** are installed and enabled.

## Application

The application is built with **Python 3.11** and **FastAPI**.

-   **Entrypoint**: `app/main.py`
-   **Worker**: `app/worker.py` listens to the `trading_signals` Redis list and saves messages to MongoDB.
-   **Deployment**: The app is deployed using `docker-compose` which orchestrates the API, Worker, Redis, and MongoDB containers.

## Security Features

-   **Firewall**: Strict inbound rules allowing only SSH and Web traffic.
-   **SSH Keys**: Access to the Droplet is secured via SSH keys (no password login).
-   **Secrets Management**: Sensitive credentials (database URLs) are passed as environment variables both in the Droplet and in the CI/CD pipeline.
-   **Private Registry**: Docker images are stored in a private DigitalOcean Container Registry.
-   **Webserver**: Nginx  filter and harden the traffic before it reaches the application. 
-   **SSL**: All traffic is encrypted using Let's Encrypt certificates.

## CI/CD Pipelines

This repository uses **GitHub Actions** for automation.

### 1. Infrastructure Pipeline (`infra.yaml`)
Triggers on changes to the `infra/` directory.
-   **Pull Requests**: Runs `terraform plan` to preview changes before applying.
-   **Master Branch**: Runs `terraform apply` to provision changes.

### 2. Application Pipeline (`app.yaml`)
Triggers on changes to the `app/` directory.
-   **Build**: Builds the Docker image and pushes it to the DigitalOcean Container Registry.
-   **Deploy**: Connects to the Droplet via SSH, pulls the new image, and updates the running containers using `docker compose`.

## Setup & Secrets

To use the CI/CD pipelines, you must configure the following **GitHub Secrets**:

| Secret Name | Description |
| :--- | :--- |
| `DIGITALOCEAN_TOKEN` | API Token for DigitalOcean. Permissions: all(droplet,registry,firewall), read/write(spaces), read(region). |
| `AWS_ACCESS_KEY_ID` | Access Key for the Spaces Object Storage (Terraform Backend). |
| `AWS_SECRET_ACCESS_KEY` | Secret Key for the Spaces Object Storage. |
| `HOST` | IP Address of the Droplet (for deployment). |
| `USERNAME` | SSH Username (root). |
| `SSH_KEY_DO` | Private SSH Key for accessing the Droplet. |
| `PASSPHRASE` | Passphrase for the SSH Key (if applicable). |
| `HOSTNAME` | Domain name of the Droplet (optional). |

## Local Development

To run the application locally:

### API only.

1.  **Prerequisites**: Python 3.11, pip, virtualenv.
2.  **Run**:
    ```bash
    cd app/
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    fastapi dev
    ```

### Full stack.

1.  **Prerequisites**: Docker and Docker Compose.
2.  **Run**:
    ```bash
    cd app/
    docker build -t pyron-api:latest .
    
    cd infra
    change L4 at infra/docker-compose.yaml to use the local image(pyron-api:latest)
    docker compose up --build -d 
    ```

### Load Testing

1.  **Prerequisites**: k6.
2.  **Run**:
    ```bash
    k6 run infra/load_test.js --summary-export=stats.json > load_test_results.txt 2>&1
    ```
3. **Check results**:
    ```bash
    cat load_test_results.txt
    cat stats.json
    ```
Note: My Average latency is around 250ms, but I believe that is due the fact I'm at Bali, the server is in London, so I believe when you run the test by yourself, you will get a lower latency.



