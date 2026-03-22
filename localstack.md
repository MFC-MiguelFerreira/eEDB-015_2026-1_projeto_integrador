# Configuração do Ambiente Local (LocalStack)

Este documento descreve o passo a passo para executar e testar a nossa infraestrutura de **Landing Zone** localmente. 
Utilizamos o **LocalStack** via Docker para simular os serviços da AWS (S3, Lambda e SSM Parameter Store) no nosso próprio computador, permitindo testar a ingestão de dados pesados do Kaggle sem gerar custos no AWS Learner Lab.

## Pré-requisitos

1. **Docker e Docker Compose** instalados (Se estiver no Windows, certifique-se de que o Docker Desktop está integrado com o WSL2).
2. **Credenciais do Kaggle:** Uma conta no Kaggle com um Token de API gerado (`kaggle.json`).

---

## Passo a Passo de Execução

### Passo 1: Configurar as Credenciais (`.env`)
1. Na pasta `infrastructure/`, faça uma cópia do ficheiro `.env.example` e mude o nome para `.env`.
2. Edite o ficheiro `.env` para ficar com este formato (as credenciais da AWS devem ser "test" para forçar o uso do LocalStack, mas as do Kaggle têm de ser reais):

```env
# Credenciais reais do Kaggle (necessárias para o download)
KAGGLE_USERNAME=seu_usuario_aqui
KAGGLE_KEY=sua_chave_secreta_aqui

# Credenciais FALSAS para o simulador AWS (LocalStack)
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_SESSION_TOKEN=test

# Outras variáveis de ambiente (se necessário)
```

Passo 2: Subir a Infraestrutura
Abra o terminal na raiz do projeto (onde está o docker-compose.yaml) e execute:

Bash
docker-compose down -v
docker-compose up -d --build


Isto irá descarregar a imagem gratuita do LocalStack e construir o nosso contentor aws-setup que orquestra a criação dos recursos.

Passo 3: Acompanhar o Setup da AWS
O aws-setup.sh vai criar o bucket S3, guardar as passwords no SSM e empacotar/publicar a Lambda. Acompanhe os logs para garantir que não houve erros:

Bash
docker logs -f aws_setup
(Aguarde até ver a mensagem verde ou o texto [SUCESSO] Setup da Landing Zone na AWS simulada concluído. e depois Ctrl+C para sair dos logs).

Passo 4: O Disparo da Ingestão 
Com o ambiente pronto, vamos invocar a Lambda. A Lambda  vai descarregar e extrair 12 GB de ficheiros para o bucket em poucos minutos, respeitando a RAM e o armazenamento temporário.

Dispare a execução com o comando:

Bash
docker exec -it localstack_main awslocal lambda invoke \
    --function-name landing-zone-ingestion \
    --payload '{}' \
    /tmp/resposta_landing.json


 Atenção: O terminal ficará bloqueado durante alguns minutos a processar. Não o feche!

Quando terminar, pode ver a resposta de sucesso da função:

Bash
docker exec -it localstack_main cat /tmp/resposta_landing.json


Passo 5: Validar os Dados no S3 Simulado
Para confirmar que o histórico completo (2014, 2015 e 2016) foi devidamente particionado nas pastas da Landing Zone, execute o comando de listagem do S3:

Bash
docker exec -it localstack_main awslocal s3 ls s3://eedb015-g05-landing/raw/health_insurance/ --recursive

Se vir a lista longa de ficheiros .csv, parabéns! A sua Landing Zone está pronta!

 Como Limpar o Ambiente
Para parar os serviços e destruir os dados do bucket simulado (poupando espaço no seu disco rígido):

Bash
docker-compose down -v


Troubleshooting Comum (Docker no Windows/WSL)
Erro no Download da Imagem do LocalStack (error getting credentials...)
Se o Docker falhar ao tentar descarregar o LocalStack devido ao gestor de credenciais do Windows, execute os seguintes passos no WSL:

Apague a configuração falha: rm -f ~/.docker/config.json

Limpe a sessão: docker logout

Tente subir a infraestrutura novamente com docker-compose up -d --build.
