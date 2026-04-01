# ==============================================================================
# Dockerfile: Focado APENAS na Ingestão (Landing -> Raw Zone)
# ==============================================================================
# Usamos a imagem oficial do AWS CLI como base
FROM amazon/aws-cli:latest

# --- Instalação de Dependências ---
# Instala o Python, pip e zip (necessários para empacotar e gerir as Lambdas)
RUN yum update -y && \
    yum install -y zip python3 python3-pip && \
    yum clean all

# Define o diretório de trabalho
WORKDIR /aws

# Instala a biblioteca requests globalmente no contentor (para uso do script)
RUN pip3 install --no-cache-dir requests boto3

# O entrypoint será o nosso script de setup
ENTRYPOINT ["/aws/aws-setup.sh"]


# Configuração do Dockerfile para o ambiente de desenvolvimento com PySpark e Jupyter Notebook
# Choose your desired base image
FROM jupyter/pyspark-notebook:latest

# name your environment and choose the python version
ARG conda_env=vscode_pyspark
ARG py_ver=3.11

# you can add additional libraries you want mamba to install by listing them below the first line and ending with "&& \"
RUN mamba create --yes -p "${CONDA_DIR}/envs/${conda_env}" python=${py_ver} ipython ipykernel && \
    mamba clean --all -f -y

# alternatively, you can comment out the lines above and uncomment those below
# if you'd prefer to use a YAML file present in the docker build context

# COPY --chown=${NB_UID}:${NB_GID} environment.yml "/home/${NB_USER}/tmp/"
# RUN cd "/home/${NB_USER}/tmp/" && \
#     mamba env create -p "${CONDA_DIR}/envs/${conda_env}" -f environment.yml && \
#     mamba clean --all -f -y

# create Python kernel and link it to jupyter
RUN "${CONDA_DIR}/envs/${conda_env}/bin/python" -m ipykernel install --user --name="${conda_env}" && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# any additional pip installs can be added by uncommenting the following line
# Pin PySpark to the runtime Spark version installed in the base image
RUN "${CONDA_DIR}/envs/${conda_env}/bin/pip" install pyspark==3.5.0 pandas --no-cache-dir

# if you want this environment to be the default one, uncomment the following line:
RUN echo "conda activate ${conda_env}" >> "${HOME}/.bashrc"