# Ambiente Local — AWS Glue PySpark (Dev Container)

Este Dev Container reproduz localmente o ambiente de execução do **AWS Glue 5** usando a imagem oficial `amazon/aws-glue-libs:5`. O objetivo é permitir o desenvolvimento e teste dos scripts de ETL sem incorrer em custos de Glue no AWS Academy.

## Por que usar o Dev Container?

Os scripts de ETL do projeto rodam no **AWS Glue** (Spark gerenciado). Para desenvolver e validar a lógica localmente — sem consumir créditos — usamos um container com o mesmo runtime do Glue: PySpark, `awsglue`, `boto3` e extensões Iceberg já instalados.

Os notebooks em `scripts/` são desenvolvidos neste ambiente. Uma vez validados, o código é transportado para `src/glue_jobs/` na forma de scripts `.py` prontos para deploy no Glue.

> Para instruções sobre como executar os notebooks dentro do container, consulte o [README da pasta scripts/](../scripts/README.md).

## Pré-requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (ou Docker Engine no Linux) rodando
- [VS Code](https://code.visualstudio.com/) com a extensão **Dev Containers** instalada (`ms-vscode-remote.remote-containers`)
- Arquivo `infrastructure/.env` preenchido com as credenciais do AWS Academy (veja abaixo)

## Configurando as credenciais AWS

As credenciais do AWS Academy Learner Lab são **efêmeras** — expiram a cada sessão (~4 horas). Por isso, é necessário atualizá-las sempre que iniciar uma nova sessão no laboratório.

### 1. Copie o arquivo de exemplo

```bash
cp infrastructure/.env.example infrastructure/.env
```

### 2. Preencha o `.env` com as credenciais do Learner Lab

Acesse o painel do AWS Academy, clique em **AWS Details** → **AWS CLI** e copie os valores para o arquivo `infrastructure/.env`:

```dotenv
AWS_ACCESS_KEY_ID=ASIA...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=...
AWS_DEFAULT_REGION=us-east-1
```

> **Nunca commite o arquivo `.env`.** Ele está no `.gitignore`.

O arquivo `.env` é montado dentro do container em `/home/hadoop/.env` (somente leitura). O script `setup-aws-credentials.sh` lê esse arquivo e gera `~/.aws/credentials` e `~/.aws/config` automaticamente ao criar o container.

## Abrindo o projeto no Dev Container

1. Abra o VS Code na raiz do projeto.
2. Pressione `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**.
3. Aguarde o build da imagem e a execução do `postCreateCommand` (primeira vez pode demorar alguns minutos).
4. O workspace será montado em `/home/hadoop/workspace` dentro do container.

As portas **4040** (Spark UI) e **18080** (Spark History Server) são encaminhadas automaticamente para o host.

## Atualizando as credenciais sem recriar o container

As credenciais expiram a cada sessão do Learner Lab. Para atualizá-las **sem destruir e recriar o container**:

### Via VS Code Task (recomendado)

1. Pressione `Ctrl+Shift+P` → **Tasks: Run Task**.
2. Selecione **Refresh AWS Credentials**.

A task executa o script `setup-aws-credentials.sh` dentro do container, relendo o `.env` atualizado e sobrescrevendo `~/.aws/credentials`.

> Lembre-se de salvar o novo conteúdo no `infrastructure/.env` **antes** de rodar a task.

### Via terminal integrado

Com o terminal aberto dentro do container:

```bash
bash /home/hadoop/workspace/.devcontainer/setup-aws-credentials.sh
```

## Saindo do Dev Container

Para voltar ao ambiente local sem destruir o container:

1. Pressione `Ctrl+Shift+P` → **Dev Containers: Reopen Folder Locally**.

O container continua rodando em segundo plano e pode ser reutilizado na próxima sessão sem necessidade de rebuild. Para reconectar, basta repetir o passo **Reopen in Container**.

Para parar o container completamente (liberar recursos):

```bash
docker stop eedb015_g05_aws_glue_pyspark_environment
```

Para removê-lo e forçar um rebuild limpo na próxima abertura:

```bash
docker rm eedb015_g05_aws_glue_pyspark_environment
```
