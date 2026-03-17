# Infraestrutura — eEDB-015/2026-1

Infraestrutura como código (IaC) do projeto, provisionada via **AWS CloudFormation** no ambiente AWS Academy Learner Lab.

## Estrutura

```
infrastructure/
├── cloudformation/
│   ├── stacks/          # Templates CloudFormation, numerados por ordem de deploy
│   │   └── 01-storage.yaml
│   └── parameters/      # Valores de parâmetros por ambiente
│       └── dev.json
├── scripts/
│   ├── deploy.sh        # Cria ou atualiza um stack
│   └── destroy.sh       # Remove um stack (com confirmação)
├── .env.example         # Modelo de credenciais (versionado)
└── .env                 # Credenciais reais — NÃO commitado (.gitignore)
```

## Pré-requisitos

- AWS CLI instalado e configurado com as credenciais do Learner Lab
- As credenciais são **efêmeras** e mudam a cada nova sessão do Learner Lab

## Configurando as credenciais

Os scripts carregam automaticamente as credenciais de `infrastructure/.env`. Use o arquivo de exemplo como ponto de partida:

```bash
cp infrastructure/.env.example infrastructure/.env
# edite o .env com os valores da tela "AWS Details" do Learner Lab
```

O `.env` está no `.gitignore` e **nunca será commitado**. O `.env.example` é o modelo versionado para referência dos membros do grupo.

## Stacks disponíveis

| #   | Stack        | Descrição                                                     |
| --- | ------------ | ------------------------------------------------------------- |
| 01  | `01-storage` | Buckets S3 das camadas Landing, Bronze, Silver, Gold + Athena |

## Como fazer deploy

```bash
# Da raiz do repositório:
./infrastructure/scripts/deploy.sh 01-storage
```

O script executa `aws cloudformation deploy`, que cria o stack se não existir ou aplica apenas as mudanças (changeset) se já existir. Ao final, exibe os Outputs com os nomes e ARNs dos recursos criados.

## Como remover um stack

```bash
./infrastructure/scripts/destroy.sh 01-storage
```

> **Atenção:** os buckets de dados (Landing, Bronze, Silver, Gold) têm `DeletionPolicy: Retain` e **não são deletados** junto com o stack — isso protege os dados de uma remoção acidental. Para deletar os buckets, esvazie-os manualmente no console S3 antes.
