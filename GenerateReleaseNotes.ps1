<#
.SYNOPSIS
  Generiert Release Notes aus den mit einem Build verknüpften Work Items in Azure DevOps (On-Premise).

.DESCRIPTION
  Dieses Skript ruft über die Azure DevOps REST API alle Work Items ab, die einem angegebenen Build zugeordnet sind,
  oder sucht Work Items basierend auf Tags. Anschließend werden zusätzlich alle übergeordneten Elemente (bis zur EPIC-Ebene) geladen.
  Es wird ein Hierarchiebaum (mit Parent‑Referenzen) aufgebaut und gefiltert. Work Items können über IncludeTags eingeschlossen
  und über ExcludeTags ausgeschlossen werden. Features und Epics ohne Kinder werden automatisch entfernt.
  Die Release Notes werden in Markdown, HTML und optional als Word-Dokument (DOCX) ausgegeben.

.PARAMETER ServerUrl
  Basis-URL deines TFS/DevOps-Servers inkl. Collection, z. B. "http://meinserver:8080/tfs/DefaultCollection".

.PARAMETER Project
  Der Name des Projekts, z. B. "meinProjekt".

.PARAMETER BuildIds
  Kommagetrennte Liste von Build-IDs, für die die Release Notes erzeugt werden sollen (z.B. "1234,1235,1236"). 
  Optional - wenn nicht angegeben, wird nach Tags gesucht.

.PARAMETER IncludeTags
  Kommagetrennte Liste von Tags, nach denen gefiltert werden soll (z.B. "Release,Sprint5").
  Wenn BuildId angegeben ist, werden die Build-Work-Items nach diesen Tags gefiltert.
  Wenn keine BuildId angegeben ist, werden Work Items mit diesen Tags gesucht.

.PARAMETER TagOperator
  Bestimmt die Verknüpfung der Tags: "OR" (mindestens ein Tag) oder "AND" (alle Tags müssen vorhanden sein).
  Standard: "OR"

.PARAMETER ExcludeTags
  Kommagetrennte Liste von Tags, die ausgeschlossen werden sollen (z.B. "KRN,Test").
  Work Items mit einem dieser Tags werden herausgefiltert.

.PARAMETER Pat
  Dein Personal Access Token (PAT) für die Authentifizierung.

.PARAMETER TemplatePath
  Der Dateipfad zum Template (Markdown oder HTML), z. B. "C:\Templates\ReleaseTemplate.md".

.PARAMETER OutputPath
  Der Dateipfad, wo die generierten Release Notes gespeichert werden sollen, z. B. "C:\Ausgabe\ReleaseNotes.md".

.EXAMPLE
  .\GenerateReleaseNotes.ps1 -ServerUrl "http://meinserver:8080/tfs/DefaultCollection" -Project "meinProjekt" -BuildId 1234 -IncludeTags "Release,Sprint5" -Pat "DEIN_PAT_HIER" -TemplatePath "C:\Templates\ReleaseTemplate.md" -OutputPath "C:\Ausgabe\ReleaseNotes.md"

.EXAMPLE
  .\GenerateReleaseNotes.ps1 -ServerUrl "http://meinserver:8080/tfs/DefaultCollection" -Project "meinProjekt" -IncludeTags "Release" -Pat "DEIN_PAT_HIER"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ServerUrl = "",
    
    [Parameter(Mandatory = $true)]
    [string]$Project,
    
    [Parameter(Mandatory = $false)]
    [string]$BuildIds = "",
    
    [Parameter(Mandatory = $false)]
    [string]$IncludeTags = "",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("OR", "AND")]
    [string]$TagOperator = "OR",
    
    [Parameter(Mandatory = $false)]
    [string]$ExcludeTags = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Pat,
    
    [Parameter(Mandatory = $false)]
    [string]$TemplatePath,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

# Stelle sicher, dass TLS 1.2 verwendet wird
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -----------------------------
# Funktion zum Logging
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

# --- Standardwerte setzen, wenn Parameter null oder leer sind ---
if ([string]::IsNullOrEmpty($Project)) {
    if (-not [string]::IsNullOrEmpty($env:SYSTEM_TEAMPROJECT)) {
        $Project = $env:SYSTEM_TEAMPROJECT
    }
    else {
        $Project = "DefaultProject"
    }
}

# URL-Decode des Projektnamens für WIQL-Queries (falls URL-encoded übergeben)
# Verwende native PowerShell-Methode statt System.Web (funktioniert überall)
$ProjectDecoded = [Uri]::UnescapeDataString($Project)

if (-not $Pat -or $Pat -eq "") {
    if ($env:SYSTEM_ACCESSTOKEN) {
        $Pat = $env:SYSTEM_ACCESSTOKEN
    }
    else {
        Write-Error "Kein Personal Access Token (PAT) oder System Access Token verfügbar!"
        exit 1
    }
}

if ([string]::IsNullOrEmpty($TemplatePath)) {
    # Nutze das Verzeichnis, in dem sich das Skript befindet
    $TemplatePath = Join-Path -Path $PSScriptRoot -ChildPath "Template.md"
    Write-Log "Template: $TemplatePath"
}

if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path -Path $PSScriptRoot -ChildPath "ReleaseNotes.md"
    Write-Log "Output: $OutputPath"
}

# -----------------------------
# Funktion: Abrufen der Work Item-Details
function Get-WorkItemDetails {
    param (
        [int[]]$Ids,
        [string]$ServerUrl,
        [string]$Project,
        [hashtable]$Headers
    )
    if ($Ids.Count -eq 0) { return $null }
    $idsParam = $Ids -join ','
    $detailsUrl = "$ServerUrl/$Project/_apis/wit/workitems?ids=$idsParam&api-version=7.0&`$expand=Relations"
    Write-Log "Rufe Details für Work Items ab: $idsParam"
    try {
        Write-Log "Sende Anfrage für Work Item Details..."
        $response = Invoke-RestMethod -Uri $detailsUrl -Headers $Headers -Method Get
        Write-Log "Work Item Details-Antwort erhalten: $($response.value.Count) Items"
        return $response.value
    } catch {
        Write-Log "FEHLER beim Abrufen der Work Item-Details:"
        Write-Log "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Log "Exception Message: $($_.Exception.Message)"
        Write-Log "URL: $detailsUrl"
        if ($_.Exception.InnerException) {
            Write-Log "Inner Exception: $($_.Exception.InnerException.Message)"
        }
        Write-Error "Fehler beim Abrufen der Work Item-Details: $($_.Exception.Message)"
        return $null
    }
}

# -----------------------------
# Funktion: Work Items anhand von Tags suchen
function Get-WorkItemsByTags {
    param (
        [string]$ServerUrl,
        [string]$Project,
        [string]$ProjectDecoded,
        [hashtable]$Headers,
        [string[]]$Tags,
        [string]$Operator = "OR"
    )
    
    if ($Tags.Count -eq 0) {
        Write-Log "Keine Tags für die Suche angegeben."
        return @()
    }
    
    # Erstelle WIQL-Query für Tag-Suche
    $tagConditions = @()
    foreach ($tag in $Tags) {
        $tagConditions += "[System.Tags] CONTAINS '$tag'"
    }
    $tagQuery = $tagConditions -join " $Operator "
    
    $wiqlQuery = @{
        query = "SELECT [System.Id] FROM WorkItems WHERE ($tagQuery) AND [System.TeamProject] = '$ProjectDecoded'"
    } | ConvertTo-Json
    
    $wiqlUrl = "$ServerUrl/$Project/_apis/wit/wiql?api-version=7.0"
    Write-Log "Suche Work Items mit Tags ($Operator): $($Tags -join ', ')"
    Write-Log "WIQL-URL: $wiqlUrl"
    Write-Log "WIQL-Query: $wiqlQuery"
    Write-Log "Project (URL-encoded): $Project"
    Write-Log "Project (decoded): $ProjectDecoded"
    
    try {
        Write-Log "Sende WIQL-Anfrage..."
        $wiqlResponse = Invoke-RestMethod -Uri $wiqlUrl -Headers $Headers -Method Post -Body $wiqlQuery -ContentType "application/json; charset=utf-8"
        Write-Log "WIQL-Antwort erfolgreich erhalten"
        
        if (-not $wiqlResponse.workItems -or $wiqlResponse.workItems.Count -eq 0) {
            Write-Log "Keine Work Items mit den angegebenen Tags gefunden."
            return @()
        }
        
        Write-Log "Verarbeite $($wiqlResponse.workItems.Count) Work Items aus WIQL-Antwort..."
        $foundIds = $wiqlResponse.workItems | ForEach-Object { $_.id }
        Write-Log "$($foundIds.Count) Work Items mit passenden Tags gefunden."
        return $foundIds
    } catch {
        Write-Log "FEHLER bei der Tag-Suche - Details:"
        Write-Log "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Log "Exception Message: $($_.Exception.Message)"
        if ($_.Exception.InnerException) {
            Write-Log "Inner Exception: $($_.Exception.InnerException.Message)"
        }
        Write-Log "Script Stack Trace: $($_.ScriptStackTrace)"
        Write-Error "Fehler bei der Tag-Suche: $($_.Exception.Message)"
        return @()
    }
}

# -----------------------------
# Funktion: Alle relevanten Work Items (inkl. übergeordneter Elemente) abrufen
function Get-AllWorkItems {
    param (
        [int[]]$BuildIdArray,
        [string]$ServerUrl,
        [string]$Project,
        [string]$ProjectDecoded,
        [hashtable]$Headers,
        [string[]]$IncludeTagsArray = @(),
        [string]$TagOperator = "OR",
        [string[]]$ExcludeTagsArray = @()
    )
    
    $initialIds = @()
    
    Write-Log "Get-AllWorkItems gestartet mit BuildIdArray.Count=$($BuildIdArray.Count), IncludeTagsArray.Count=$($IncludeTagsArray.Count)"
    
    # Entscheide, ob Build-basiert oder Tag-basiert gesucht wird
    if ($BuildIdArray.Count -gt 0) {
        # 1. Abrufen der direkt mit den Builds verknüpften Work Items
        foreach ($buildId in $BuildIdArray) {
            $buildWiUrl = "$ServerUrl/$Project/_apis/build/builds/$buildId/workitems?api-version=7.0&`$top=500"
            Write-Log "Rufe Build Work Items ab für Build-ID $buildId"
            try {
                $buildWiResponse = Invoke-RestMethod -Uri $buildWiUrl -Headers $Headers -Method Get
                if ($buildWiResponse.value -and $buildWiResponse.value.Count -gt 0) {
                    $initialIds += $buildWiResponse.value | ForEach-Object { $_.id }
                    Write-Log "$($buildWiResponse.value.Count) Work Items für Build-ID $buildId gefunden."
                } else {
                    Write-Log "Keine Work Items für Build-ID $buildId gefunden."
                }
            } catch {
                Write-Error "Fehler beim Abrufen der Build Work Items für Build-ID ${buildId}: $($_.Exception.Message)"
            }
        }
        
        # Deduplizieren der IDs
        $initialIds = $initialIds | Sort-Object -Unique
        
        if ($initialIds.Count -eq 0) {
            Write-Log "Keine Work Items für die angegebenen Build-IDs gefunden."
            return @()
        }
    } else {
        # Suche basierend auf Tags
        if ($IncludeTagsArray.Count -eq 0) {
            Write-Log "Weder BuildId noch IncludeTags angegeben. Keine Work Items können abgerufen werden."
            return @()
        }
        $initialIds = Get-WorkItemsByTags -ServerUrl $ServerUrl -Project $Project -ProjectDecoded $ProjectDecoded -Headers $Headers -Tags $IncludeTagsArray -Operator $TagOperator
        if ($initialIds.Count -eq 0) {
            return @()
        }
    }

    # 3. Details der initialen Work Items abrufen
    $allWorkItems = @{}
    Write-Log "Rufe Details für $($initialIds.Count) initiale Work Items ab..."
    $initialWorkItems = Get-WorkItemDetails -Ids $initialIds -ServerUrl $ServerUrl -Project $Project -Headers $Headers
    Write-Log "Work Item Details erfolgreich abgerufen: $($initialWorkItems.Count) Items"
    
    # Wenn IncludeTags angegeben sind und BuildIds verwendet wurden, filtere nach Tags
    if ($BuildIdArray.Count -gt 0 -and $IncludeTagsArray.Count -gt 0) {
        Write-Log "Filtere Work Items nach IncludeTags ($TagOperator): $($IncludeTagsArray -join ', ')"
        $initialWorkItems = $initialWorkItems | Where-Object {
            $itemTags = $_.fields.'System.Tags'
            if (-not $itemTags) { return $false }
            
            if ($TagOperator -eq "AND") {
                # Alle Tags müssen vorhanden sein
                foreach ($tag in $IncludeTagsArray) {
                    if ($itemTags -notmatch "\b$tag\b") {
                        return $false
                    }
                }
                return $true
            } else {
                # Mindestens ein Tag muss vorhanden sein (OR)
                foreach ($tag in $IncludeTagsArray) {
                    if ($itemTags -match "\b$tag\b") {
                        return $true
                    }
                }
                return $false
            }
        }
        Write-Log "$($initialWorkItems.Count) Work Items nach Tag-Filterung übrig."
        
        if ($initialWorkItems.Count -eq 0) {
            Write-Log "Keine Work Items nach Tag-Filterung gefunden."
            return @()
        }
    }
    
    # ExcludeTags Filter anwenden
    if ($ExcludeTagsArray.Count -gt 0) {
        Write-Log "Filtere Work Items aus mit ExcludeTags: $($ExcludeTagsArray -join ', ')"
        $initialWorkItems = $initialWorkItems | Where-Object {
            $itemTags = $_.fields.'System.Tags'
            if (-not $itemTags) { return $true }  # Keine Tags = nicht ausschließen
            
            # Work Item ausschließen, wenn es einen der ExcludeTags hat
            foreach ($excludeTag in $ExcludeTagsArray) {
                if ($itemTags -match "\b$excludeTag\b") {
                    return $false
                }
            }
            return $true
        }
        Write-Log "$($initialWorkItems.Count) Work Items nach ExcludeTags-Filterung übrig."
        
        if ($initialWorkItems.Count -eq 0) {
            Write-Log "Keine Work Items nach ExcludeTags-Filterung gefunden."
            return @()
        }
    }
    
    foreach ($wi in $initialWorkItems) {
        $allWorkItems[$wi.id] = $wi
    }

    # 4. Rekursives Abrufen der übergeordneten Elemente (bis zur EPIC-Ebene)
    $toProcessIds = @()
    foreach ($wi in $initialWorkItems) {
        if ($wi.Relations) {
            $parentRelations = $wi.Relations | Where-Object { $_.rel -eq "System.LinkTypes.Hierarchy-Reverse" }
            foreach ($parent in $parentRelations) {
                $parentId = [int]($parent.url.Split('/')[-1])
                if (-not $allWorkItems.ContainsKey($parentId)) {
                    $toProcessIds += $parentId
                }
            }
        }
    }
    while ($toProcessIds.Count -gt 0) {
        $uniqueIds = $toProcessIds | Sort-Object -Unique
        $toProcessIds = @()
        $parentWorkItems = Get-WorkItemDetails -Ids $uniqueIds -ServerUrl $ServerUrl -Project $Project -Headers $Headers
        if ($parentWorkItems -eq $null) { break }
        foreach ($wi in $parentWorkItems) {
            if (-not $allWorkItems.ContainsKey($wi.id)) {
                $allWorkItems[$wi.id] = $wi
                Write-Log "Elternelement abgerufen: Typ=$($wi.fields.'System.WorkItemType'), Titel=$($wi.fields.'System.Title')"
                if ($wi.fields.'System.WorkItemType' -ne "Epic" -and $wi.Relations) {
                    $parentRels = $wi.Relations | Where-Object { $_.rel -eq "System.LinkTypes.Hierarchy-Reverse" }
                    foreach ($parent in $parentRels) {
                        $parentId = [int]($parent.url.Split('/')[-1])
                        if (-not $allWorkItems.ContainsKey($parentId)) {
                            $toProcessIds += $parentId
                        }
                    }
                }
            }
        }
    }
    return $allWorkItems.Values
}

# -----------------------------
# Funktion: Hierarchische Struktur der Work Items aufbauen
function Build-Hierarchy {
    param (
        [array]$WorkItems
    )
    $workItemsById = @{}
    foreach ($wi in $WorkItems) {
        $workItemsById[$wi.id] = $wi
    }
    foreach ($wi in $WorkItems) {
        $wi | Add-Member -MemberType NoteProperty -Name Children -Value @() -Force
    }
    $roots = @()
    foreach ($wi in $WorkItems) {
        $isChild = $false
        if ($wi.Relations) {
            $parentRels = $wi.Relations | Where-Object { $_.rel -eq "System.LinkTypes.Hierarchy-Reverse" }
            foreach ($parent in $parentRels) {
                $parentId = [int]($parent.url.Split('/')[-1])
                if ($workItemsById.ContainsKey($parentId)) {
                    $workItemsById[$parentId].Children += $wi
                    $isChild = $true
                }
            }
        }
        if (-not $isChild) {
            $roots += $wi
        }
    }
    return $roots
}

# -----------------------------
# Neue Funktion: Filter-Tree
function Filter-Tree {
    param (
        [array]$Nodes
    )
    $filteredNodes = @()
    foreach ($node in $Nodes) {
        # 1. Rekursives Filtern der Kinder
        if ($node.Children -and $node.Children.Count -gt 0) {
            $node.Children = Filter-Tree -Nodes $node.Children
        }

        # 2. Features ohne Kinder entfernen
        if (($node.fields.'System.WorkItemType' -eq "Feature") -and ($node.Children.Count -eq 0)) {
            Write-Log "Feature $($node.id) ohne Kinder wird entfernt."
            continue
        }
        # 3. Epics ohne Kinder entfernen
        if (($node.fields.'System.WorkItemType' -eq "Epic") -and ($node.Children.Count -eq 0)) {
            Write-Log "Epic $($node.id) ohne Kinder wird entfernt."
            continue
        }

        $filteredNodes += $node
    }
    return $filteredNodes
}

# -----------------------------
# Funktion: Formatierung der Release Notes mit Nummerierung (Markdown)
function Format-ReleaseNotes {
    param (
        [array]$HierarchyItems,
        [string]$Prefix = "",
        [int]$Level = 1,
        [string]$ServerUrl,
        [string]$Project
    )
    $notes = ""
    $counter = 1

    foreach ($item in $HierarchyItems) {
        $currentNumber = if ($Prefix -eq "") { "$counter" } else { "$Prefix.$counter" }
        $counter++

        $title = $item.fields.'System.Title'
        $id = $item.id
        $type  = $item.fields.'System.WorkItemType'

        switch ($type) {
            "Epic"                  { $headerPrefix = "## " }        # Überschrift 2
            "Feature"               { $headerPrefix = "### " }       # Überschrift 3
            "Product Backlog Item"  { $headerPrefix = "#### " }      # Überschrift 4
            "Bug"                   { $headerPrefix = "##### " }     # Überschrift 5
            default                 { $headerPrefix = ("#" * ($Level + 1)) + " " }
        }

        if ($type -ieq "Product Backlog Item") {
            $headerLine = "$headerPrefix $currentNumber Item: $title ($id)"
        }
        elseif ($type -ieq "Bug") {
            $headerLine = "$headerPrefix $currentNumber Fehler: $title ($id)"
        }
        else {
            $headerLine = "$headerPrefix $currentNumber $title ($id)"
        }

        $notes += $headerLine + "`n`n"

        if ($type -ieq "Product Backlog Item") {
            if ($item.fields.'System.Description') {
                $notes += $item.fields.'System.Description' + "`n`n"
            }
        }
        elseif ($type -ieq "Bug") {
            if ($item.fields.'Microsoft.VSTS.TCM.ReproSteps') {
                $notes += $item.fields.'Microsoft.VSTS.TCM.ReproSteps' + "`n`n"
            }
        }
        else {
            if (($item.Children.Count -eq 0) -and $item.fields.'System.Description') {
                $notes += $item.fields.'System.Description' + "`n`n"
            }
        }

        if (@($item.Children).Count -gt 0) {
            $sortedChildren = $item.Children | Sort-Object -Property {
                switch ($_.fields.'System.WorkItemType') {
                    "Epic"                  { 1 }
                    "Feature"               { 2 }
                    "Product Backlog Item"  { 3 }
                    "Bug"                   { 4 }
                    default                 { 5 }
                }
            }
            $notes += Format-ReleaseNotes -HierarchyItems $sortedChildren -Prefix $currentNumber -Level ($Level + 1) -ServerUrl $ServerUrl -Project $Project
        }
    }
    return $notes
}


# -----------------------------
# Neue Funktion: Formatierung der Release Notes als HTML (ohne Styling)
function Format-ReleaseNotesHTML {
    param (
        [array]$HierarchyItems,
        [string]$Prefix = "",
        [int]$Level = 1,
        [string]$ServerUrl,
        [string]$Project
    )
    $html = ""
    $counter = 1
    foreach ($item in $HierarchyItems) {
        $currentNumber = if ($Prefix -eq "") { "$counter" } else { "$Prefix.$counter" }
        $counter++
        $title = $item.fields.'System.Title'
        $id = $item.id
        $type = $item.fields.'System.WorkItemType'
        
        if ($type -ieq "Product Backlog Item") {
            # PBIs erhalten die Formatvorlage "PBI" und beginnen mit "Item:"
            $headerContent = "Item: $title ($id)"
            $html += "<p style=""mso-style-name:'PBI';"">$headerContent</p>`n"
        }
        elseif ($type -ieq "Bug") {
            # Bugs erhalten die Formatvorlage "Bug" und beginnen mit "Fehler:"
            $headerContent = "Fehler: $title ($id)"
            $html += "<p style=""mso-style-name:'Bug';"">$headerContent</p>`n"
        }
        else {
            switch ($type) {
                "Epic"    { $headerTag = "h2" }
                "Feature" { $headerTag = "h3" }
                default   { 
                    $headerLevel = $Level + 1
                    if ($headerLevel -gt 6) { $headerLevel = 6 }
                    $headerTag = "h$headerLevel" 
                }
            }
            $headerContent = "$currentNumber $title ($id)"
            $html += "<$headerTag>$headerContent</$headerTag>`n"
        }
        
        # Ausgabe der Beschreibungen oder Reproduktionsschritte
        if ($type -ieq "Product Backlog Item") {
            if ($item.fields.'System.Description') {
                $desc = $item.fields.'System.Description'
                $html += "<p>$desc</p>`n"
            }
        }
        elseif ($type -ieq "Bug") {
            if ($item.fields.'Microsoft.VSTS.TCM.ReproSteps') {
                $steps = $item.fields.'Microsoft.VSTS.TCM.ReproSteps'
                $html += "<p>$steps</p>`n"
            }
        }
        else {
            if (($item.Children.Count -eq 0) -and $item.fields.'System.Description') {
                $desc = $item.fields.'System.Description'
                $html += "<p>$desc</p>`n"
            }
        }
        
        # Rekursiver Aufruf für untergeordnete Elemente
        if (@($item.Children).Count -gt 0) {
            $sortedChildren = $item.Children | Sort-Object -Property {
                switch ($_.fields.'System.WorkItemType') {
                    "Epic"                  { 1 }
                    "Feature"               { 2 }
                    "Product Backlog Item"  { 3 }
                    "Bug"                   { 4 }
                    default                 { 5 }
                }
            }
            $html += Format-ReleaseNotesHTML -HierarchyItems $sortedChildren -Prefix $currentNumber -Level ($Level + 1) -ServerUrl $ServerUrl -Project $Project
        }
    }
    return $html
}


# -----------------------------
# Hauptlogik

# Parse BuildIds in Array
$BuildIdArray = @()
if (-not [string]::IsNullOrWhiteSpace($BuildIds)) {
    $BuildIdArray = $BuildIds.Split(',') | ForEach-Object { 
        $trimmed = $_.Trim()
        if ($trimmed -match '^\d+$') { [int]$trimmed } 
    } | Where-Object { $_ -gt 0 }
    if ($BuildIdArray.Count -gt 0) {
        Write-Log "Build-IDs: $($BuildIdArray -join ', ')"
    }
}

if ($BuildIdArray.Count -gt 0) {
    Write-Log "Starte Generierung der Release Notes für Build-IDs $($BuildIdArray -join ', ') im Projekt '$Project'."
} else {
    Write-Log "Starte Generierung der Release Notes basierend auf Tags im Projekt '$Project'."
}

# Parse IncludeTags in Array
$IncludeTagsArray = @()
if (-not [string]::IsNullOrWhiteSpace($IncludeTags)) {
    $IncludeTagsArray = $IncludeTags.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    Write-Log "IncludeTags: $($IncludeTagsArray -join ', ')"
}

# Parse ExcludeTags in Array
$ExcludeTagsArray = @()
if (-not [string]::IsNullOrWhiteSpace($ExcludeTags)) {
    $ExcludeTagsArray = $ExcludeTags.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    Write-Log "ExcludeTags: $($ExcludeTagsArray -join ', ')"
}

# Validierung: Mindestens BuildIds oder IncludeTags muss vorhanden sein
if ($BuildIdArray.Count -eq 0 -and $IncludeTagsArray.Count -eq 0) {
    Write-Error "Entweder BuildIds oder IncludeTags muss angegeben werden!"
    exit 1
}

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
$headers = @{ Authorization = "Basic $base64AuthInfo" }

$allWorkItems = Get-AllWorkItems -BuildIdArray $BuildIdArray -ServerUrl $ServerUrl -Project $Project -Headers $headers -IncludeTagsArray $IncludeTagsArray -TagOperator $TagOperator -ExcludeTagsArray $ExcludeTagsArray -ProjectDecoded $ProjectDecoded
if (-not $allWorkItems -or $allWorkItems.Count -eq 0) {
    Write-Log "Keine Work Items gefunden. Füge Nachricht in die Release Notes ein."
    if ($BuildIdArray.Count -gt 0) {
        $buildList = $BuildIdArray -join ', '
        $fullContent = "# Release Notes für Builds $buildList`n`nEs wurden keine Work Items für diese Builds gefunden.`n"
    } else {
        $fullContent = "# Release Notes`n`nEs wurden keine Work Items mit den angegebenen Tags gefunden.`n"
    }

    if (Test-Path $TemplatePath) {
        $templateContent = Get-Content -Path $TemplatePath -Raw
        $templateContent = $templateContent -replace "\{\{ReleaseNotes\}\}", $fullContent
        $templateContent | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Log "Release Notes gespeichert unter '$OutputPath' unter Verwendung des Templates."
    } else {
        $fullContent | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Log "Release Notes gespeichert unter '$OutputPath'."
    }
    
    exit 0
}

$hierarchyRoots = Build-Hierarchy -WorkItems $allWorkItems
$hierarchyRoots = Filter-Tree -Nodes $hierarchyRoots

# Erzeuge Markdown-Inhalt
if ($BuildIdArray.Count -gt 0) {
    $buildList = $BuildIdArray -join ', '
    $headerContent = "# Release Notes für Builds $buildList`n`n"
} else {
    $headerContent = "# Release Notes (Tags: $($IncludeTagsArray -join ', '))`n`n"
}
$releaseNotesContent = Format-ReleaseNotes -HierarchyItems $hierarchyRoots -ServerUrl $ServerUrl -Project $Project
$fullContent = $headerContent + $releaseNotesContent

if (Test-Path $TemplatePath) {
    $templateContent = Get-Content -Path $TemplatePath -Raw
    $templateContent = $templateContent -replace "\{\{ReleaseNotes\}\}", $fullContent
    $templateContent | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Log "Markdown Release Notes gespeichert unter '$OutputPath' unter Verwendung des Templates."
} else {
    $fullContent | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Log "Markdown Release Notes gespeichert unter '$OutputPath'."
}

# -----------------------------
# Neuer Block: Erzeuge Word-Dokument (DOCX) aus den Markdown Release Notes mit Pandoc
if (Get-Command pandoc -ErrorAction SilentlyContinue) {
    $OutputPathWord = $OutputPath -replace "\.md$", ".docx"
    & pandoc $OutputPath -o $OutputPathWord
    Write-Log "Word Release Notes gespeichert unter '$OutputPathWord'."
} else {
    Write-Log "Pandoc ist nicht installiert, daher wird kein Word-Dokument erzeugt."
}

# -----------------------------
# Erzeuge HTML-Inhalt
if ($BuildIdArray.Count -gt 0) {
    $buildList = $BuildIdArray -join ', '
    $htmlHeader = "<html><head><meta charset='utf-8'></head><body><h1>Release Notes für Builds $buildList</h1>`n"
} else {
    $htmlHeader = "<html><head><meta charset='utf-8'></head><body><h1>Release Notes (Tags: $($IncludeTagsArray -join ', '))</h1>`n"
}
$htmlBody = Format-ReleaseNotesHTML -HierarchyItems $hierarchyRoots -ServerUrl $ServerUrl -Project $Project
$htmlFooter = "</body></html>"
$fullHtmlContent = $htmlHeader + $htmlBody + "`n" + $htmlFooter

# Bestimme den HTML-Ausgabepfad (z.B. ReleaseNotes.html statt ReleaseNotes.md)
if ($OutputPath -match "\.md$") {
    $OutputPathHtml = $OutputPath -replace "\.md$", ".html"
} else {
    $OutputPathHtml = "$OutputPath.html"
}
$fullHtmlContent | Out-File -FilePath $OutputPathHtml -Encoding UTF8
Write-Log "HTML Release Notes gespeichert unter '$OutputPathHtml'."

