# Plano de Execução: Automação com Spotless

## Objetivo
Substituir scripts manuais de licenciamento por uma solução integrada ao build (Gradle), garantindo que todo arquivo `.java` e `.kt` possua o cabeçalho da licença MIT e siga os padrões de formatação (Google Java Style / ktlint).

## 1. Configuração no `build.gradle.kts`
Para cada módulo (`generic-orchestrator`, `service-portal-bff`, `service-portal-manager`), adicionar o plugin e sua configuração:

```kotlin
plugins {
    id("com.diffplug.spotless") version "6.25.0"
}

spotless {
    java {
        // Aplica o cabeçalho da licença MIT
        licenseHeaderFile("${rootProject.projectDir}/license-header.txt")
        
        // Padroniza com Google Java Style
        googleJavaFormat().aosp()
        
        targetExclude("**/build/**", "**/generated/**")
    }
    
    // Apenas para o service-portal-manager (Kotlin)
    kotlin {
        licenseHeaderFile("${rootProject.projectDir}/license-header.txt")
        
        // Padroniza com ktlint
        ktlint()
        
        targetExclude("**/build/**")
    }
}
```

## 2. Comandos Principais

- **Aplicar formatação e licença**:
  ```bash
  ./gradlew spotlessApply
  ```

- **Verificar conformidade (Check)**:
  ```bash
  ./gradlew spotlessCheck
  ```
  *(Dica: Este comando deve ser incluído em futuras pipelines de CI).*

## 3. Integração com o Git
Uma vez que o Spotless esteja configurado, o script `/scripts/apply-license-header.sh` torna-se obsoleto.

### Ação:
- Remover o script manual para evitar conflitos de lógica.
- Adicionar a execução do `spotlessCheck` como um passo obrigatório antes de cada release.

---
*Gerado para garantir a integridade do Service Portal.*