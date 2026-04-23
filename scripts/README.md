# scripts/ — Notebooks de Desenvolvimento e Documentação

Esta pasta contém notebooks Jupyter usados para **desenvolvimento e validação** dos scripts ETL do projeto, além de documentos de design das camadas do Data Lake. Os notebooks são projetados para rodar no ambiente local do Dev Container, sem custos de Glue no AWS Academy.

## Relação com os artefatos de produção

```
scripts/*.ipynb         →   (validado)   →   src/glue_jobs/*.py
  (desenvolvimento                           (versão final para
   e teste local)                             deploy no AWS Glue)

scripts/*.ipynb         →   (exploração)  →   src/.sql/
  (análise Silver)                            (queries Gold prontas
                                               para orquestração)
```

Cada notebook ETL corresponde a um Glue Job. Uma vez que a lógica está validada, o código é adaptado para script `.py` em `src/glue_jobs/`, substituindo as variáveis locais pelos parâmetros do job (`getResolvedOptions`).

## Notebooks disponíveis

| Notebook | Artefato correspondente | Descrição |
|---|---|---|
| `landing_to_bronze.ipynb` | `src/glue_jobs/landing_to_bronze.py` | Ingere CSVs da Landing Zone e grava tabelas Iceberg na camada Bronze |
| `bronze_exploration.ipynb` | *(exploração — sem job correspondente)* | Lista todas as tabelas do database Bronze e exibe as 10 primeiras linhas de cada uma via Amazon Athena |
| `silver_exploration.ipynb` | *(exploração — sem job correspondente)* | Explora as tabelas da camada Silver: schema tipado, amostra, perfil de nulos e estatísticas. Resultados consolidados em `silver_exploration.md` |
| `bronze_to_silver.ipynb` | `src/glue_jobs/bronze_to_silver.py` | Protótipo das transformações Bronze → Silver: tipagem, deduplicação e criação das tabelas Iceberg na Silver |

## Documentos de design

| Documento | Descrição |
|---|---|
| [`silver_exploration.md`](silver_exploration.md) | Referência consolidada da camada Silver: schemas, distribuições, estatísticas e regras críticas de JOIN para desenvolvimento da Gold |
| [`silver_to_gold.md`](silver_to_gold.md) | Modelagem completa da camada Gold: esquema estrela, tabelas de fato/dimensão, regras Silver → Gold, particionamento e referências às queries em `src/.sql/` |

## Como executar

Os notebooks devem ser executados **dentro do Dev Container**, que fornece o runtime do AWS Glue (PySpark + `awsglue` + extensões Iceberg) e as credenciais AWS configuradas.

Consulte o [README do Dev Container](../.devcontainer/README.md) para instruções de como abrir o ambiente e configurar as credenciais do AWS Academy.

### Passos rápidos

1. Abra o projeto no Dev Container (`Ctrl+Shift+P` → **Dev Containers: Reopen in Container**).
2. Atualize as credenciais AWS via task **Refresh AWS Credentials** se a sessão do Learner Lab tiver expirado.
3. Abra o notebook desejado.
4. Selecione o kernel **Python 3.11.14** no canto superior direito do notebook.
5. Execute as células sequencialmente.

> O kernel **Python 3.11.14** corresponde ao ambiente Conda `vscode_pyspark` configurado no container, que já inclui PySpark, `awsglue` e todas as dependências necessárias. Selecionar outro kernel resultará em erros de importação.

## Diferenças entre notebook e script de produção

Os notebooks têm algumas adaptações para execução local que **não existem** nos scripts de produção:

| Aspecto | Notebook (`scripts/`) | Script de produção (`src/glue_jobs/`) |
|---|---|---|
| Parâmetros | Variáveis hardcoded no notebook | `getResolvedOptions(sys.argv, [...])` |
| Limite de tabelas | `LOCAL_TABLE_LIMIT = 3` (evita sobrecarga) | Sem limite — processa tudo |
| Inicialização do Job | Comentado | `job = Job(glue_ctx); job.init(...)` |
