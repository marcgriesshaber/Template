# Azure DevOps Release Notes Generator

Automatische Generierung von Release Notes aus Azure DevOps Work Items mit flexibler Tag- und Build-basierter Filterung.

## 📋 Übersicht

Dieses PowerShell-Skript generiert professionelle Release Notes aus Azure DevOps Work Items. Es unterstützt:

- ✅ Build-basierte oder Tag-basierte Work Item-Suche
- ✅ Hierarchische Darstellung (Epic → Feature → PBI/Bug)
- ✅ Flexible Tag-Filterung (Include/Exclude)
- ✅ Multiple Ausgabeformate (Markdown, HTML, DOCX)
- ✅ Template-Unterstützung
- ✅ Azure DevOps On-Premise und Cloud

## 🚀 Features

### Work Item-Abfrage

- **Build-basiert**: Ruft alle Work Items ab, die mit einem oder mehreren Builds verknüpft sind
- **Tag-basiert**: Sucht Work Items anhand von Tags mit OR/AND-Verknüpfung
- **Hierarchie-Erweiterung**: Lädt automatisch alle übergeordneten Elemente bis zur Epic-Ebene

### Filterung

- **IncludeTags**: Nur Work Items mit bestimmten Tags einschließen
- **ExcludeTags**: Work Items mit bestimmten Tags ausschließen
- **TagOperator**: OR (mindestens ein Tag) oder AND (alle Tags erforderlich)
- **Automatische Bereinigung**: Entfernt Features und Epics ohne Kinder

### Ausgabeformate

- **Markdown (.md)**: Mit hierarchischer Nummerierung und Überschriften
- **HTML (.html)**: Mit semantischen Tags und MSO-Formatvorlagen
- **Word (.docx)**: Via Pandoc (optional)

## 📦 Voraussetzungen

### Erforderlich

- PowerShell 5.1 oder höher
- Azure DevOps Server (On-Premise) oder Azure DevOps Services
- Personal Access Token (PAT) mit Work Items Read-Berechtigung

### Optional

- [Pandoc](https://pandoc.org/installing.html) für DOCX-Export

## 🔧 Installation

1. **Skript herunterladen**

   ```powershell
   # Klonen Sie das Repository oder laden Sie GenerateReleaseNotes.ps1 herunter
   git clone https://github.com/marcgriesshaber/Template.git
   cd Template
   ```

2. **Personal Access Token erstellen**

   - Navigieren Sie zu Azure DevOps → User Settings → Personal Access Tokens
   - Erstellen Sie ein Token mit **Work Items (Read)** Berechtigung
   - Speichern Sie das Token sicher

3. **Template erstellen (optional)**

   ```powershell
   # Erstellen Sie eine Template.md Datei im gleichen Verzeichnis
   echo "# Meine Release Notes`n`n{{ReleaseNotes}}" > Template.md
   ```

## 📖 Skript ausführen - Schritt für Schritt

### 🎯 Schnellstart für lokale Ausführung

#### Schritt 1: Personal Access Token (PAT) erstellen

1. Melden Sie sich bei Azure DevOps an
2. Klicken Sie auf Ihr Profilbild (rechts oben) → **Personal Access Tokens**
3. Klicken Sie auf **+ New Token**
4. Konfigurieren Sie den Token:
   - **Name**: z.B. "ReleaseNotes Generator"
   - **Organization**: Wählen Sie Ihre Organisation
   - **Expiration**: Setzen Sie ein Ablaufdatum
   - **Scopes**: Wählen Sie **Custom defined** → **Work Items** → **Read**
5. Klicken Sie auf **Create**
6. **WICHTIG**: Kopieren Sie den Token sofort und speichern Sie ihn sicher!

#### Schritt 2: Server-URL ermitteln

Die Server-URL hängt davon ab, ob Sie Azure DevOps Cloud oder On-Premise verwenden:

**Azure DevOps Cloud:**
```
https://dev.azure.com/IhreOrganisation/
```

**Azure DevOps Server (On-Premise):**
```
http://IhrServer:8080/tfs/DefaultCollection
```

Sie finden die URL in Ihrem Browser, wenn Sie in Azure DevOps eingeloggt sind.

#### Schritt 3: Projekt-Namen finden

Der Projekt-Name steht in Azure DevOps oben links oder in der URL:
```
https://dev.azure.com/IhreOrg/IhrProjekt/_...
                              ^^^^^^^^^^
```

#### Schritt 4: Build-ID oder Tags bestimmen

**Option A - Build-ID finden:**
1. Navigieren Sie zu **Pipelines** → **Builds**
2. Klicken Sie auf einen Build
3. Die Build-ID steht in der URL und oben im Build-Details:
   ```
   https://dev.azure.com/IhreOrg/IhrProjekt/_build/results?buildId=1234
                                                                   ^^^^
   ```

**Option B - Tags verwenden:**
1. Öffnen Sie ein Work Item in Azure DevOps
2. Sehen Sie sich das Feld **Tags** an
3. Notieren Sie die Tag-Namen (z.B. "Release", "v2.0", "Sprint5")

#### Schritt 5: Skript ausführen

**Beispiel 1 - Mit Build-ID:**
```powershell
# Passen Sie die Werte an:
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/IhreOrganisation/" `
    -Project "IhrProjekt" `
    -BuildIds "1234" `
    -Pat "IHREN_TOKEN_HIER_EINFUEGEN"
```

**Beispiel 2 - Mit Tags:**
```powershell
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/IhreOrganisation/" `
    -Project "IhrProjekt" `
    -IncludeTags "Release" `
    -Pat "IHREN_TOKEN_HIER_EINFUEGEN"
```

#### Schritt 6: Ausgabe prüfen

Das Skript erstellt im gleichen Verzeichnis:
- `ReleaseNotes.md` - Markdown-Datei
- `ReleaseNotes.html` - HTML-Datei
- `ReleaseNotes.docx` - Word-Datei (nur wenn Pandoc installiert)

### 📋 Parameter-Referenz im Detail

#### `ServerUrl` (Optional)
- **Was**: Die Basis-URL Ihres Azure DevOps Servers
- **Wo finden**: In der Browser-Adresszeile, wenn Sie in Azure DevOps eingeloggt sind
- **Format Cloud**: `https://dev.azure.com/OrganisationName/`
- **Format On-Premise**: `http://servername:8080/tfs/CollectionName`
- **Standard**: Leer (muss dann über Umgebungsvariable gesetzt werden)
- **Beispiel**: 
  ```powershell
  -ServerUrl "https://dev.azure.com/IhreOrganisation/"
  ```

#### `Project` (ERFORDERLICH)
- **Was**: Der Name oder die ID Ihres Azure DevOps Projekts
- **Wo finden**: Oben links in Azure DevOps oder in der URL
- **Tipp**: Bei Leerzeichen im Namen, verwenden Sie Anführungszeichen
- **Beispiel**: 
  ```powershell
  -Project "MeinProjekt"
  -Project "Mein Projekt"  # Mit Leerzeichen
  ```

#### `BuildIds` (Optional)
- **Was**: Eine oder mehrere Build-IDs, deren Work Items in die Release Notes sollen
- **Wo finden**: Pipelines → Builds → Build-Details (oben oder in URL)
- **Format**: Kommagetrennt, ohne Leerzeichen oder mit Leerzeichen nach Komma
- **Kombination**: Kann mit `IncludeTags` kombiniert werden
- **Beispiel**: 
  ```powershell
  -BuildIds "1234"              # Einzelner Build
  -BuildIds "1234,1235,1236"    # Mehrere Builds
  ```

#### `IncludeTags` (Optional)
- **Was**: Tags, die Work Items haben müssen, um eingeschlossen zu werden
- **Wo finden**: In den Work Items unter dem Feld "Tags"
- **Format**: Kommagetrennt, Groß-/Kleinschreibung wird beachtet
- **Kombination**: Mit `TagOperator` wird festgelegt, ob alle oder nur ein Tag erforderlich ist
- **Beispiel**: 
  ```powershell
  -IncludeTags "Release"                    # Ein Tag
  -IncludeTags "Release,v2.0,Important"     # Mehrere Tags
  ```

#### `TagOperator` (Optional)
- **Was**: Bestimmt, wie mehrere `IncludeTags` verknüpft werden
- **Werte**: 
  - `"OR"` = Mindestens einer der Tags muss vorhanden sein (Standard)
  - `"AND"` = Alle Tags müssen vorhanden sein
- **Standard**: "OR"
- **Beispiel**: 
  ```powershell
  -IncludeTags "Release,Approved" -TagOperator "AND"  # Beide Tags erforderlich
  -IncludeTags "Release,Hotfix" -TagOperator "OR"     # Einer der Tags reicht
  ```

#### `ExcludeTags` (Optional)
- **Was**: Tags, die Work Items zum Ausschluss markieren
- **Wo finden**: In den Work Items unter dem Feld "Tags"
- **Format**: Kommagetrennt
- **Wirkung**: Work Items mit einem dieser Tags werden entfernt
- **Beispiel**: 
  ```powershell
  -ExcludeTags "KRN,Internal,Draft"  # Schließt alle Items mit diesen Tags aus
  ```

#### `Pat` (Optional, aber empfohlen)
- **Was**: Personal Access Token für die Authentifizierung
- **Wo erstellen**: Azure DevOps → User Settings → Personal Access Tokens
- **Berechtigung**: Work Items (Read)
- **Standard**: Verwendet `$env:SYSTEM_ACCESSTOKEN` (nur in Pipelines verfügbar)
- **Sicherheit**: NIEMALS im Code speichern!
- **Beispiel**: 
  ```powershell
  -Pat "IHREN_TOKEN_HIER_EINFUEGEN"
  
  # Besser: Aus Umgebungsvariable
  $pat = $env:AZURE_DEVOPS_PAT
  -Pat $pat
  ```

#### `TemplatePath` (Optional)
- **Was**: Pfad zu einer Markdown-Template-Datei
- **Format**: Das Template muss `{{ReleaseNotes}}` als Platzhalter enthalten
- **Standard**: `Template.md` im Skript-Verzeichnis
- **Beispiel**: 
  ```powershell
  -TemplatePath "C:\Templates\MeinTemplate.md"
  -TemplatePath ".\Vorlagen\ReleaseTemplate.md"  # Relativer Pfad
  ```
  
  **Template-Beispiel:**
  ```markdown
  # Release Notes - $(Get-Date -Format "MMMM yyyy")
  
  {{ReleaseNotes}}
  
  ---
  *Generiert am $(Get-Date -Format "dd.MM.yyyy HH:mm")*
  ```

#### `OutputPath` (Optional)
- **Was**: Pfad, wo die Release Notes gespeichert werden sollen
- **Format**: Muss auf `.md` enden (HTML und DOCX werden automatisch generiert)
- **Standard**: `ReleaseNotes.md` im Skript-Verzeichnis
- **Automatisch**: `.html` und `.docx` werden mit gleichem Namen erstellt
- **Beispiel**: 
  ```powershell
  -OutputPath "C:\Releases\Sprint42_ReleaseNotes.md"
  # Erstellt auch: Sprint42_ReleaseNotes.html und Sprint42_ReleaseNotes.docx
  ```

### 🔄 Kombinierte Parameter-Beispiele

#### Beispiel 1: Nur Build-basiert
```powershell
# Holt alle Work Items von Build 1234
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/MeineOrg/" `
    -Project "MeinProjekt" `
    -BuildIds "1234" `
    -Pat $env:AZURE_PAT
```

#### Beispiel 2: Nur Tag-basiert (OR)
```powershell
# Holt Work Items mit Tag "Release" ODER "Hotfix"
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/MeineOrg/" `
    -Project "MeinProjekt" `
    -IncludeTags "Release,Hotfix" `
    -TagOperator "OR" `
    -Pat $env:AZURE_PAT
```

#### Beispiel 3: Nur Tag-basiert (AND)
```powershell
# Holt Work Items mit Tag "Release" UND "Approved"
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/MeineOrg/" `
    -Project "MeinProjekt" `
    -IncludeTags "Release,Approved" `
    -TagOperator "AND" `
    -Pat $env:AZURE_PAT
```

#### Beispiel 4: Build mit Tag-Filter
```powershell
# Holt Work Items von Build 1234, aber nur die mit Tag "Release"
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/MeineOrg/" `
    -Project "MeinProjekt" `
    -BuildIds "1234" `
    -IncludeTags "Release" `
    -Pat $env:AZURE_PAT
```

#### Beispiel 5: Mit Ausschluss-Tags
```powershell
# Holt Work Items mit "Release", aber schließt "Internal" und "Draft" aus
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/MeineOrg/" `
    -Project "MeinProjekt" `
    -IncludeTags "Release" `
    -ExcludeTags "Internal,Draft" `
    -Pat $env:AZURE_PAT
```

#### Beispiel 6: Mehrere Builds mit Filter
```powershell
# Holt Work Items von 3 Builds, filtert nach "Release", schließt "KRN" aus
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/MeineOrg/" `
    -Project "MeinProjekt" `
    -BuildIds "1234,1235,1236" `
    -IncludeTags "Release" `
    -ExcludeTags "KRN" `
    -Pat $env:AZURE_PAT
```

#### Beispiel 7: Mit Template und Custom Output
```powershell
# Vollständiges Beispiel mit allen Optionen
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/MeineOrg/" `
    -Project "MeinProjekt" `
    -IncludeTags "Sprint42,Release" `
    -TagOperator "AND" `
    -ExcludeTags "Draft" `
    -TemplatePath ".\Templates\Sprint.md" `
    -OutputPath ".\Output\Sprint42_Release.md" `
    -Pat $env:AZURE_PAT
```

### 🔑 PAT sicher verwenden

**NIEMALS im Skript:**
```powershell
# ❌ FALSCH - Token im Code!
-Pat "NIEMALS_ECHTEN_TOKEN_HIER"
```

**Besser - Umgebungsvariable:**
```powershell
# ✅ RICHTIG - Token in Umgebungsvariable
# 1. Token in Umgebungsvariable setzen
$env:AZURE_DEVOPS_PAT = "IHREN_TOKEN_HIER"

# 2. Verwenden
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "https://dev.azure.com/MeineOrg/" `
    -Project "MeinProjekt" `
    -IncludeTags "Release" `
    -Pat $env:AZURE_DEVOPS_PAT
```

**Am besten - Secrets-Datei:**
```powershell
# 1. Erstelle eine Datei "secrets" (ohne Erweiterung)
# Inhalt:
# ServerUrl: https://dev.azure.com/MeineOrg/
# Project: MeinProjekt
# PAT: IHREN_TOKEN_HIER

# 2. Füge "secrets" zur .gitignore hinzu!
# echo "secrets" >> .gitignore

# 3. Lade die Secrets
$secretsContent = Get-Content ".\secrets" -Raw
$serverUrl = ($secretsContent | Select-String "ServerUrl: (.+)").Matches.Groups[1].Value
$project = ($secretsContent | Select-String "Project: (.+)").Matches.Groups[1].Value
$pat = ($secretsContent | Select-String "PAT: (.+)").Matches.Groups[1].Value

# 4. Verwende sie
.\GenerateReleaseNotes.ps1 `
    -ServerUrl $serverUrl `
    -Project $project `
    -IncludeTags "Release" `
    -Pat $pat
```

## 📖 Verwendung

### Basis-Beispiele

#### 1. Build-basierte Release Notes

```powershell
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "http://meinserver:8080/tfs/DefaultCollection" `
    -Project "MeinProjekt" `
    -BuildIds "1234,1235,1236" `
    -Pat "DEIN_PAT_HIER"
```

#### 2. Tag-basierte Release Notes

```powershell
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "http://meinserver:8080/tfs/DefaultCollection" `
    -Project "MeinProjekt" `
    -IncludeTags "Release,v2.0" `
    -TagOperator "AND" `
    -Pat "DEIN_PAT_HIER"
```

#### 3. Build mit Tag-Filter

```powershell
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "http://meinserver:8080/tfs/DefaultCollection" `
    -Project "MeinProjekt" `
    -BuildIds "1234" `
    -IncludeTags "Release" `
    -ExcludeTags "KRN,Internal" `
    -Pat "DEIN_PAT_HIER"
```

### Erweiterte Beispiele

#### Mit Template und Custom Output

```powershell
.\GenerateReleaseNotes.ps1 `
    -ServerUrl "http://meinserver:8080/tfs/DefaultCollection" `
    -Project "MeinProjekt" `
    -IncludeTags "Sprint42" `
    -TemplatePath "C:\Templates\MeinTemplate.md" `
    -OutputPath "C:\Releases\Sprint42_ReleaseNotes.md" `
    -Pat "DEIN_PAT_HIER"
```

#### Azure DevOps Pipeline

```yaml
steps:
- task: PowerShell@2
  displayName: 'Generate Release Notes'
  inputs:
    filePath: '$(Build.SourcesDirectory)/GenerateReleaseNotes.ps1'
    arguments: >
      -ServerUrl "$(System.CollectionUri)"
      -Project "$(System.TeamProject)"
      -BuildIds "$(Build.BuildId)"
      -IncludeTags "Release"
      -Pat "$(System.AccessToken)"
      -OutputPath "$(Build.ArtifactStagingDirectory)/ReleaseNotes.md"
```

## ⚙️ Parameter

| Parameter | Typ | Erforderlich | Standard | Beschreibung |
|-----------|-----|--------------|----------|--------------|
| `ServerUrl` | String | Nein | "" | Basis-URL des Azure DevOps Servers (z.B. `http://server:8080/tfs/DefaultCollection`) |
| `Project` | String | **Ja** | - | Projektname oder -ID |
| `BuildIds` | String | Nein | "" | Kommagetrennte Liste von Build-IDs (z.B. `"1234,1235"`) |
| `IncludeTags` | String | Nein | "" | Kommagetrennte Liste von Tags zum Einschließen (z.B. `"Release,Sprint5"`) |
| `TagOperator` | String | Nein | "OR" | Tag-Verknüpfung: `"OR"` oder `"AND"` |
| `ExcludeTags` | String | Nein | "" | Kommagetrennte Liste von Tags zum Ausschließen (z.B. `"KRN,Test"`) |
| `Pat` | String | Nein | $env:SYSTEM_ACCESSTOKEN | Personal Access Token für Authentifizierung |
| `TemplatePath` | String | Nein | "Template.md" | Pfad zur Template-Datei |
| `OutputPath` | String | Nein | "ReleaseNotes.md" | Pfad für die Ausgabedatei |

## 📝 Template-Format

Templates verwenden den Platzhalter `{{ReleaseNotes}}`:

```markdown
# Release Notes - Version 2.0

Veröffentlichungsdatum: $(Get-Date -Format "dd.MM.yyyy")

## Änderungen

{{ReleaseNotes}}

## Hinweise
- Bitte vor dem Update ein Backup erstellen
- Migrationsscript ausführen
```

## 📊 Ausgabe-Struktur

### Markdown-Beispiel

```markdown
# Release Notes für Builds 1234

## 1 Kundenverwaltung optimieren (123)

### 1.1 Performance verbessern (124)

#### 1.1.1 Item: Datenbank-Indizes hinzufügen (125)

Beschreibung des Work Items...

##### 1.1.1.1 Fehler: Timeout bei großen Abfragen (126)

Reproduktionsschritte...
```

### Hierarchie-Ebenen

- **Epic**: `## Überschrift 2`
- **Feature**: `### Überschrift 3`
- **Product Backlog Item**: `#### Überschrift 4` (mit "Item:" Präfix)
- **Bug**: `##### Überschrift 5` (mit "Fehler:" Präfix)

## 🔍 Filterlogik

### IncludeTags (OR-Modus)

```powershell
-IncludeTags "Release,Sprint5" -TagOperator "OR"
# Findet Work Items mit Tag "Release" ODER "Sprint5"
```

### IncludeTags (AND-Modus)

```powershell
-IncludeTags "Release,Approved" -TagOperator "AND"
# Findet nur Work Items mit BEIDEN Tags
```

### ExcludeTags

```powershell
-ExcludeTags "KRN,Internal"
# Entfernt alle Work Items mit Tag "KRN" oder "Internal"
```

### Kombinierte Filter

```powershell
-BuildIds "1234" -IncludeTags "Release" -ExcludeTags "Draft"
# 1. Holt Work Items von Build 1234
# 2. Filtert nach Tag "Release"
# 3. Entfernt Items mit Tag "Draft"
```

## 🛠️ Fehlerbehebung

### "Kein Personal Access Token verfügbar"

```powershell
# Lösung: PAT explizit übergeben
-Pat "DEIN_PAT_HIER"
```

### "Keine Work Items gefunden"

```powershell
# Prüfen Sie:
# 1. Sind Work Items wirklich mit dem Build verknüpft?
# 2. Stimmen die Tag-Namen exakt?
# 3. Hat der PAT die richtigen Berechtigungen?

# Debug-Ausgabe aktivieren
$VerbosePreference = "Continue"
.\GenerateReleaseNotes.ps1 -Verbose ...
```

### "Pandoc ist nicht installiert"

```powershell
# Word-Export (DOCX) benötigt Pandoc
# Installation:
# Windows: choco install pandoc
# oder Download von https://pandoc.org/installing.html
```

### URL-Encoding-Probleme

```powershell
# Projekt-Namen mit Leerzeichen werden automatisch dekodiert
# "My%20Project" wird zu "My Project"
```

## 📁 Ausgabedateien

Das Skript erstellt folgende Dateien:

```text
ReleaseNotes.md          # Markdown-Version
ReleaseNotes.html        # HTML-Version
ReleaseNotes.docx        # Word-Version (wenn Pandoc installiert)
```

### HTML-Features

- UTF-8 Encoding
- MSO-Formatvorlagen für Word-Kompatibilität
- Semantische HTML-Tags (h2, h3, h4, p)
- Spezielle Styles für PBI und Bug

## 🔐 Sicherheit

### Best Practices

- ✅ Verwenden Sie PAT mit minimalen Berechtigungen (nur Work Items Read)
- ✅ Speichern Sie PAT niemals im Quellcode
- ✅ Setzen Sie Ablaufdatum für PAT

### In Azure Pipelines

```yaml
variables:
- group: 'release-notes-secrets'  # Variable Group mit PAT

steps:
- task: PowerShell@2
  inputs:
    arguments: '-Pat "$(AzureDevOpsPAT)"'
  env:
    SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

---

**Version:** 1.0  
**Letztes Update:** November 2025

