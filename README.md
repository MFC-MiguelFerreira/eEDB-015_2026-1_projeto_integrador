# Projeto Integrador eEDB-015/2026-1

Repositório do Projeto Integrador da disciplina eEDB-015/2026-1 — Curso de Especialização em Big Data, Escola Politécnica da USP.

## Integrantes

| Nome            |
| --------------- |
| Ingrid Silva    |
| Lucas Pereira   |
| Miguel Ferreira |
| Simone Pereira  |

## Objetivo do Projeto

Este projeto aplica na prática os conhecimentos adquiridos ao longo do curso de Especialização em Big Data, construindo um pipeline de dados completo — da ingestão bruta até uma entrega visual em BI — sobre o dataset [Health Insurance Marketplace (Kaggle)](https://www.kaggle.com/datasets/hhs/health-insurance-marketplace).

O dataset contém dados detalhados sobre planos de saúde e odontológicos oferecidos nos EUA entre 2014 e 2016. O desafio central é a fragmentação dos dados em arquivos anuais isolados.

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

## Estrutura do Repositório

```
.
├── infrastructure/   # IaC (CloudFormation) e scripts de deploy na AWS
├── src/              # Scripts de produção (Glue Jobs e Lambdas)
├── scripts/          # Notebooks de desenvolvimento e teste local
└── .devcontainer/    # Ambiente local que replica o runtime do AWS Glue
```

### Por onde começar

**1. Infraestrutura AWS** — [`infrastructure/`](infrastructure/README.md)
Provisionamento dos recursos AWS (S3, Glue, Lambda, Athena) via CloudFormation. Contém os scripts de deploy e as instruções para configurar as credenciais efêmeras do AWS Academy Learner Lab.

**2. Ambiente de desenvolvimento local** — [`.devcontainer/`](.devcontainer/README.md)
Container Docker que replica o runtime do AWS Glue 5 localmente (PySpark + `awsglue` + Iceberg). Use-o para desenvolver e testar os scripts sem consumir créditos AWS. Inclui instruções para abrir o ambiente no VS Code e atualizar as credenciais entre sessões.

**3. Desenvolvimento de scripts ETL** — [`scripts/`](scripts/README.md)
Notebooks Jupyter para prototipação dos Glue Jobs. Todo script novo deve ser desenvolvido aqui primeiro — dentro do Dev Container — e só transportado para `src/` após validado.

**4. Scripts de produção** — [`src/`](src/README.md)
Versões finais dos Glue Jobs (`.py`) e Lambdas prontos para deploy na AWS. Não edite diretamente sem antes validar a lógica no notebook correspondente em `scripts/`.