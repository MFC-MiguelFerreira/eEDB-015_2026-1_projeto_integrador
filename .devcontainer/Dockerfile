FROM amazon/aws-glue-libs:5

USER root

# Install extra tools if needed
RUN pip install --upgrade pip \
    && pip install ipykernel awswrangler

# Install Claude Code (native binary)
RUN curl -fsSL https://claude.ai/install.sh | bash

RUN echo "conda activate vscode_pyspark" >> /home/hadoop/.bashrc
