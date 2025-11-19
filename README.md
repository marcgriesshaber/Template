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
- ✅ Nutzen Sie Umgebungsvariablen oder Azure Key Vault
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

## 🤝 Beiträge

Contributions sind willkommen! Bitte:

1. Forken Sie das Repository
2. Erstellen Sie einen Feature-Branch (`git checkout -b feature/AmazingFeature`)
3. Committen Sie Ihre Änderungen (`git commit -m 'Add AmazingFeature'`)
4. Pushen Sie zum Branch (`git push origin feature/AmazingFeature`)
5. Öffnen Sie einen Pull Request

## 📜 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe [LICENSE](LICENSE) für Details.

## 👥 Autoren

- **Marc Griesshaber** - *Initial work* - [@marcgriesshaber](https://github.com/marcgriesshaber)

## 🙏 Danksagungen

- Azure DevOps REST API Dokumentation
- PowerShell Community
- Pandoc für Dokumenten-Konvertierung

## 📞 Support

Bei Fragen oder Problemen:

- Erstellen Sie ein [Issue](https://github.com/marcgriesshaber/Template/issues)
- Kontaktieren Sie den Autor

## 🗺️ Roadmap

- [ ] Unterstützung für zusätzliche Work Item-Typen
- [ ] PDF-Export
- [ ] Grafische Darstellung der Hierarchie
- [ ] Email-Versand der Release Notes
- [ ] Change-Log zwischen Builds
- [ ] Multi-Language Support

---

**Version:** 1.0  
**Letztes Update:** November 2025

