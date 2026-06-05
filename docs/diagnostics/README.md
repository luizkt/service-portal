# Padrão de Nomenclatura para Diagnósticos

Para garantir a rastreabilidade e organização dos incidentes e investigações técnicas, todos os novos arquivos nesta pasta devem seguir o padrão abaixo:

## Formato do Nome
`YYYY-MM-DD-[TIPO]-[COMPONENTE]-[descrição-curta].md`

### Campos:
1. **Data (YYYY-MM-DD)**: Data do registro (permite ordenação alfabética por data).
2. **Tipo**:
   - `INCIDENTE`: Problema crítico em execução.
   - `INVESTIGACAO`: Análise técnica de comportamento inesperado.
   - `RESOLUTION`: Documentação de como um problema foi corrigido.
   - `POST-MORTEM`: Lições aprendidas após uma falha grave.
3. **Componente**: `ORCHESTRATOR`, `MANAGER`, `BFF`, `FRONTEND` ou `INFRA`.
4. **Descrição**: Texto curto separado por hifens.

---

## Estrutura sugerida do Conteúdo
1. **Sumário Executivo**: O que aconteceu em 2 frases.
2. **Causa Raiz**: Onde estava o erro (código, config, infra).
3. **Evidências**: Logs, prints ou comandos `curl` que demonstram o erro.
4. **Resolução**: Passo a passo da correção.
5. **Ações Preventivas**: O que fazer para não repetir (ex: novos alertas no Grafana).

---
*Este padrão foi estabelecido em Junho de 2026 para suportar a escala do Service Portal.*