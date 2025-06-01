# DevSecOps CI/CD Container Security Project

## Introduction
This project is my attempt to create an end-to-end DevSecOps pipeline for a minimal Flask web application. The objective was to:

1. **Develop** a lightweight Flask service with version-injection capabilities.
2. **Containerize** the service with Docker, passing build-time metadata (Git SHA, build date).
3. **Automate security scanning** by integrating Trivy into GitHub Actions, rejecting images with HIGH/CRITICAL vulnerabilites. 
4. **Deploy** to a local Kubernetes (Minikube) cluster, verifying container readiness and networking. 
5. **Document** design decisions and security considerations. 

## Architecture Overview
![](/images/architecture.png)

## Functional Components

### 1. Flask Application (/app)
- `app/routes.py`
   - Defines four endpoints
      - `/` ─ renders index.html, injecting `GIT_SHA` and `BUILD DATE`
      - `/version` ─ returns JSON  `[ "git_sha": ..., "build_date": ...]`
      - `/greet` ─ presents a form (GET) and echoes a name (POST) 
      - `/hello/<name>` ─ simple route to render greeting template
      - *Note `/greet` and `/hello/<name>` were implemented during initial Flask & Route experimental stage. These routes will be deleted in the near future. 
   - `app/templates/`
      - `index.html` ─ displays the verion metadata and "Raw/version" link.
      - `hello.html` ─ Jinja template for personalized greetings. 
      - `greet_form.html` - HTML form to collect a name.
      - *Note `hello.html` and `greet_form.html` were implemented during initial Flask & Route experimental stage. These routes will be deleted in the near future.
   - `run.py`
      - Entrypoint that binds Flask to `0.0.0.0:5000` and disables debug mode in production:
      ```python
      from app import app
      import os

      if __name__ == "__main__":
         app.run(
         host="0.0.0.0",
         port=int(os.getenv("PORT", 5000)),
         debug=False
      )
      ```
      - Ensures Kubernetes can route external traffic into container.
### 2. Docker Configuration (`Dockerfile`)
- Base Image
   ```dockerfile
   FROM python:3.9-slim-buster
   ```
   - Slim-buster variant reduces attack surface. 
- Build Arguments & Environment
   ```dockerfile
   ARG GIT_SHA
   ARG BUILD_DATE

   # After installing dependencies:
   ENV GIT_SHA=$GIT_SHA
   ENV BUILD_DATE=$BUILD_DATE
   ```
   - `ARG` declarations allow passing metadata at `docker build`.
   - `ENV` lines propogate them into the container runtime, accessible via `os.getenv()`.
- Dependency Installation
   ```dockerfile
   COPY requirements.txt .
   RUN pip install --no-cache-dir -r requirements.txt
   ```
   - Installs exactly-pinned packages; any vulnerable version triggers a Trivy scan failure.
- Application Copy & Non-Root User
   ```dockerfile
   COPY . .

   RUN groupadd --gid 1000 appuser \
   && useradd --uid 1000 --gid appuser --shell /bin/bash --create-home appuser
   USER appuser
   ```
   - Creates `appuser` (UID/GID 1000) and switches context, adhereing to container least-priviledge best practice. 
- Port Exposure & Entrypoint
   ```dockerfile
   EXPOSE 5000
   CMD ["flask", "run", "--host=0.0.0.0"]
   ```
### 3. GitHub Actions Workflow `(.github/workflows/ci-build-scan.yml)`
   A single job, `build-and-scan`, executes on `push` and `pull_requests`:
   ```yaml
   name: CI Build & Security Scan
   on: [push, pull_request]
   permissions:
   actions: read
   contents: read
   security-events: write


   jobs:
   build-and-scan:
      runs-on: ubuntu-latest
      permissions:
         contents: read
         security-events: write
      steps:
         - name: Checkout repository
         uses: actions/checkout@v4

         - name: Build Docker image
         run: |
            BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            GIT_SHA=${{ github.sha }}

            docker build \
            --build-arg GIT_SHA=${GIT_SHA} \
            --build-arg BUILD_DATE=${BUILD_GATE} \
            -t ttapp:${GIT_SHA} .


         - name: Scan Docker image with Trivy and export SARIF
         uses: aquasecurity/trivy-action@master
         with:
            image-ref: 'ttapp:${{ github.sha }}'
            format: sarif
            output: trivy-report.sarif
            #1: Blocks pushed commits with HIGH/CRITICAL vulnerability
            #0: Does not block pushed commits with HIGH/CRITICAL vulernability
            exit-code: 1
            severity: HIGH,CRITICAL

         - name: Upload SARIF to Github Security
         uses: github/codeql-action/upload-sarif@v3
         with: 
            sarif_file: trivy-report.sarif
   ```
   - Step 1: Checkout
      - Retrieves the latest code, inlcuding `Dockerfile`, `app/`, and workflow definitions.
   - Step 2: Docker Build
      - Captures `BUILD_DATE` (UTC ISO-8601) and `GIT_SHA` (`${{ github.sha }}`).
      - Passes them into `docker build` via `─build-arg`.
      - Tags the image as `ttapp:<GIT_SHA>`, ensuring every build is traceable.
   - Step 3: Trivy Scan
      - Calls the `aquasecurity/trivy-action` to analyze `ttapp:<GIT_SHA>`.
      - Flags any HIGH or CRITICAL CVEs in OS packages or Python Dependencies → `exit-code: 1` fails the job. 
      - Output a SARIF file (`trivy-report.sarif`)
   - Step 4: SARIF Upload
      - Uses `github/codeql-action/upload-sarif@v3` to send findings to GitHub Security tab.
      - Annotates pull requests with vulnerability details when present. 
### 4. Kubernetes Deployement and Exposure
   #### A. Build the image inside MiniKube
      1. Start MiniKube
         ```bash
         minikube start
         ```
      2. Point Docker CLI to Minikube's Docker daemon
         ```bash
         eval $(minikube docker-env)
         ```
      3. Rebuild the Docker image with the same metadata
         ```bash
         docker build \
         --build-arg GIT_SHA=$(git rev-parse HEAD) \
         --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
         -t devops_cicd:onMiniKube .
         ```
         - This ensures `devops_cicd:onMiniKube` exists in Minikube's local registry.
   #### B. Create Deployment and Service
      1. Create Kubernetes Deployment
         ```bash
         kubectl create deployment devops-cicd \
         --image=devops_cicd:onMiniKube
         ```
         - Pod spec:
            - `containers[0].image = devops_cicd:onMiniKube`
            - Defaults to 1 replica
         - Internally, the Pod's container runs Flask on `0.0.0.0:5000`, reading `GIT_SHA` and `BUILD_DATE` from the environment. 
      2. Expose via NodePort Service
         ```bash
            kubectl expose deployment devops-cicd \
         --type=NodePort \
         --port=5000
         ```
      - Assigns a NodePort to forward external traffic → Pod port 5000.
      - Command output shows:
         ```bash
         service/devops-cicd/exposed
         ```
      3. Verify Pod & Service
         ![](/images/minikube_service.png)
      4. Access the Application
         - `minikube service`
            ```bash
            minikube service devops_cicd --url
            ```
            - Opens a tunnel to the NodePort, providing a localhost-based URL.
### 5. Does it work?
![](/images/flask-app-working.png)
Looks like it does!
## Conclusion
This project was meant to be an introduction to development security, but as a software engineer, I realize that with some more development, I can implement this CI/CD pipeline across my various existing and future personal projects. Currently, this pipeline can handle the following: 

1. Vulnerability Scanning of the Container Image (Trivy)
2. Immutable, Versioned Container Builds
3. Pinning Dependencies
4. Minimal Base Image & Non-Root User
5. CI Permissions & SARIF Upload Configuration
6. Failure-First Gating
7. Kubernetes Readiness & Networking Checks


## Goals for the Future
1. Make the Pipeline Modular and Language Agnostic
2. Identify & Integrate Language-Specific Scanners
3. Add "Centralized" Secrets & Environment Management
4. Harden the Container Runtime (Minimal "Production-lite")
5. Automate Regular Dependency Updates
6. Basic Runtime Monitoring & Alerts
7. Keep It Lean

TDLR: Mostly automated but lightweight. 








      

