# src/ — Scripts de Produção

Esta pasta contém os scripts finais prontos para deploy na AWS. Todo código aqui foi previamente validado nos notebooks de desenvolvimento em `scripts/`.

## Estrutura

```
src/
├── glue_jobs/               # Scripts PySpark deployados no AWS Glue
│   ├── bronze_to_silver.py
│   └── landing_to_bronze.py
└── lambdas/                 # Funções Lambda deployadas via deploy_lambda.sh
    └── landing_zone_ingestion/
        ├── handler.py
        └── requirements.txt
```

## glue_jobs/

Scripts PySpark executados pelo **AWS Glue** (Spark gerenciado). Cada arquivo corresponde a um Glue Job provisionado via CloudFormation.

| Script | Glue Job | Stack CloudFormation |
|---|---|---|
| `landing_to_bronze.py` | `eedb015-landing-to-bronze` | `04-glue-etl` |
| `bronze_to_silver.py` | `eedb015-bronze-to-silver` | `04-glue-etl` |

O deploy é feito pelo script `infrastructure/scripts/deploy_glue_jobs.sh`, que faz upload dos `.py` para o bucket Landing Zone e atualiza o stack CloudFormation correspondente.

> Para desenvolver ou modificar um Glue Job, trabalhe primeiro no notebook equivalente em `scripts/`. Quando a lógica estiver validada, traga as alterações para o script `.py` aqui.

## lambdas/

Funções Lambda que rodam fora do Spark. Cada subpasta é uma função independente com seu próprio `requirements.txt`.

| Subpasta | Função Lambda | Responsabilidade |
|---|---|---|
| `landing_zone_ingestion/` | `LandingZoneIngestionFunction` | Download dos CSVs do Kaggle e upload para a Landing Zone (S3) |

O deploy é feito pelo script `infrastructure/scripts/deploy_lambda.sh`, que empacota o código com as dependências em um ZIP e atualiza o stack `02-lambda-ingestion`.
