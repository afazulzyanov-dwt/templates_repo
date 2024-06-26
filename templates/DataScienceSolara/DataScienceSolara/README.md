---
display_name: Solara Based Project
description: Solara Template for Coder
icon: ../../../site/static/emojis/1f4e6.png
maintainer_github: digitalwavetechnology
tags: []
---
# Solara-Based Project Documentation

## Overview

This documentation provides a comprehensive guide to setting up and running a Solara-based project. The process involves cloning a Git repository, installing necessary dependencies, configuring environment variables, and launching the server using Uvicorn.

## Workflow

The setup and execution of the project startup script makes following steps:

1. **Clone the Git Repository**:
    - The script clones the Git repository using the provided credentials and a specified git tag.
    - If a git tag is not provided, the script clones the repository to the most recent commit on the `main` branch.

2. **Install Dependencies**:
    - The script installs the necessary dependencies by running the command:
      ```bash
      pip install -r {repository}/requirements.txt
      ```

3. **Setup `SOLARA_APP` Environment Variable**:
    - Set the `SOLARA_APP` environment variable based on your project structure. For example:
      ```bash
      export SOLARA_APP=main.ipynb
      ```

4. **Run Uvicorn Server**:
    - The script starts the Uvicorn server with the following flags:
      ```bash
      uvicorn --reload-dir ./ --reload-include "*.*" --reload-exclude=*checkpoint.ipynb --reload
      ```

## Solara Project Structure

A typical Solara project structure includes the following files:


{repository}
- ├── main.ipynb               # Mandatory file
- └── requirements.txt         # Optional file

### Notes

- `main.ipynb` is mandatory and serves as the entry point of the application.
- `requirements.txt` is optional but recommended for managing dependencies.

