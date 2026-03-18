# CLAUDE.md — Projeto Integrador eEDB-015/2026-1

## Contexto do Projeto

Projeto da disciplina **Projeto Integrador (eEDB-015/2026-1)** do Curso de Especialização em Big Data da Escola Politécnica da USP.

**Domínio:** Mercado de Seguros de Saúde dos EUA (Health Insurance Marketplace), criado sob o Affordable Care Act.

**Problema central:** Os dados públicos são fragmentados em arquivos anuais isolados (2014-2016+). O projeto visa ingerir, unificar e rastrear temporalmente esses dados usando o arquivo Crosswalk para criar uma "Linhagem do Plano" — permitindo análises sobre inflação médica e "desertos de cobertura".

**Dataset:** [Health Insurance Marketplace – Kaggle](https://www.kaggle.com/datasets/hhs/health-insurance-marketplace)

### Questões de Projeto

**1. Estrutura de custos em tratamentos oncológicos**
Como evoluiu a relação entre Copay e Coinsurance para tratamentos de Câncer (Quimioterapia e Radioterapia) nos planos de 2014 a 2016? Qual categoria de plano minimiza a exposição financeira total do paciente com doenças crônicas que exigem terapia de infusão recorrente?

**2. Competição e precificação por estado**
Qual é a correlação entre a densidade de competição — medida pelo número de seguradoras operando num mesmo estado — e o valor médio do prêmio cobrado ao consumidor final?

**3. Benefícios como variável de precificação**
Os benefícios fornecidos pelo plano são a única variável que influencia no valor final? É possível classificá-los e quantificar o peso de cada categoria sobre o preço do plano?

**4. Tamanho da rede e preço do plano**
Qual é a relação entre a amplitude da rede de prestadores (Network Size) de uma seguradora e o preço final do plano? Seguradoras com redes menores conseguem oferecer preços significativamente mais baixos no mesmo estado?

**5. Monopólios e desigualdade geográfica** *(objetivo extra)*
A ausência de concorrência entre seguradoras em determinadas Áreas de Serviço cria um efeito de monopólio que infla artificialmente os prêmios dos planos básicos, em comparação com mercados altamente competitivos em grandes centros urbanos?

## Arquitetura AWS (Data Lake em Medallion)

Todo o projeto roda no **AWS Academy (Learner Lab)** respeitando limites de crédito.

```
Kaggle CSV → Landing Zone (S3)
                    ↓
             Bronze (Raw CSVs)
                    ↓  [AWS Glue Jobs / Lambda]
             Silver (Parquet limpos + Crosswalk aplicado)
                    ↓  [AWS Glue Jobs / Lambda]
              Gold (Agregados prontos para análise)
                    ↓
               Amazon Athena (consultas SQL)
```

### Serviços Utilizados

| Categoria     | Serviço               | Função                                                                   |
| ------------- | --------------------- | ------------------------------------------------------------------------ |
| Armazenamento | Amazon S3             | Camadas Bronze, Silver e Gold com versionamento e criptografia (SSE)     |
| Ingestão      | AWS Lambda            | Fazer o download e inserir os dados na camada Landing Zone               |
| Catalogação   | AWS Glue Data Catalog | Manter metadados organizados e pesquisáveis                              |
| ETL           | AWS Glue Jobs (Spark) | Transformações pesadas (join Rate × ServiceArea, aplicação do Crosswalk) |
| Orquestração  | AWS Step Functions    | Dependência entre jobs (ex: Atributos antes de Preços)                   |
| Análise       | Amazon Athena         | Consultas SQL diretas sobre arquivos no S3                               |
| Segurança     | AWS IAM               | Roles com privilégio mínimo por camada                                   |
| Monitoramento | Amazon CloudWatch     | Alertas e logs de falha nos pipelines                                    |

### Convenção de Camadas S3

- **Landing Zone:** CSVs brutos do Kaggle sem modificação
- **Bronze:** Dados brutos versionados, particionados por ano
- **Silver:** Dados limpos em Parquet, Crosswalk aplicado, dados de "Preço" tratados como confidenciais (anonimizados)
- **Gold:** Agregados e métricas prontos para cada análise de membro

## Convenções de Código

- **Linguagem principal:** Python 3.x (scripts Glue/Lambda) + SQL (Athena)
- **Formato de armazenamento processado:** Parquet (compressão Snappy)
- **Particionamento S3:** `s3://bucket/layer/year=YYYY/state=XX/`
- **Testes:** Módulo Python de testes unitários validando a lógica do Crosswalk (amostra de 100 planos que mudaram de ID entre 2015 e 2016)
- **Segurança:** Nunca commitar credenciais AWS. Usar variáveis de ambiente ou IAM Roles
- **Notebooks:** Jupyter para exploração/análise; scripts `.py` para ETL em produção

## Desafios da Disciplina

- **Cibersegurança:** Criptografia em repouso (S3-SSE) + IAM com privilégio mínimo por camada
- **Testabilidade:** Testes unitários em Python para validar o pipeline de Crosswalk

## Instruções para o Claude

- **Sempre responda em português**
- Prefira soluções simples e diretas — evite over-engineering
- Ao criar ou modificar código, atualize a documentação relevante (este CLAUDE.md, docstrings, READMEs de subpastas)
- Considere sempre os limites de crédito do AWS Academy: prefira soluções serverless (Glue, Lambda, Athena) a clusters EC2/EMR persistentes
- Ao sugerir código ETL, leve em conta que os arquivos de Rate têm milhões de linhas — otimize para processamento distribuído (Spark/Glue)
- Facilite a compreensão para todos os membros do grupo: adicione comentários explicativos no código e mantenha documentações atualizadas
