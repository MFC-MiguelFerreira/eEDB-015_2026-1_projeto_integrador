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