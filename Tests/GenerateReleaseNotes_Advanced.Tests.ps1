<#
.SYNOPSIS
    Pester-Tests für GenerateReleaseNotes_Advanced.ps1

.DESCRIPTION
    Testet alle internen Funktionen des Skripts ohne echte Azure DevOps API-Aufrufe.
    REST-API und Dateioperationen werden über Pester-Mocks simuliert.

    Voraussetzungen:
        Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck

    Ausführen:
        Invoke-Pester -Path .\Tests\ -Output Detailed
#>

# ---------------------------------------------------------------------------
# Datei-weites Setup: Mocks setzen und Skript dot-sourcen
# ---------------------------------------------------------------------------
BeforeAll {

    # Hilfsfunktion: erstellt ein minimales Work-Item-Objekt für Tests
    function New-WI {
        param(
            [int]    $Id,
            [string] $Type        = 'Product Backlog Item',
            [string] $Title       = "Test $Id",
            [string] $Description = '',
            [string] $ReproSteps  = '',
            [string] $Tags        = '',
            [array]  $Children    = @(),
            [array]  $Relations   = $null
        )
        return [PSCustomObject]@{
            id        = $Id
            fields    = [PSCustomObject]@{
                'System.WorkItemType'           = $Type
                'System.Title'                  = $Title
                'System.Description'            = $Description
                'Microsoft.VSTS.TCM.ReproSteps' = $ReproSteps
                'System.Tags'                   = $Tags
            }
            Children  = $Children
            Relations = $Relations
        }
    }

    # Hilfsfunktion: erstellt eine Hierarchy-Reverse-Relation (Kind → Elternteil)
    function New-ParentRelation {
        param([int]$ParentId, [string]$BaseUrl = 'http://server')
        return [PSCustomObject]@{
            rel = 'System.LinkTypes.Hierarchy-Reverse'
            url = "$BaseUrl/workitems/$ParentId"
        }
    }

    # --- API-Mocks: erlauben sauberes Durchlaufen der Haupt-Logik beim Dot-Source ---

    # Invoke-RestMethod: gibt synthetische Daten zurück (Success-Pfad, kein exit 0)
    Mock Invoke-RestMethod {
        param($Uri)
        if ($Uri -match '/build/builds/\d+/workitems') {
            # Build-Work-Items-Endpunkt: 1 Work Item gefunden
            return [PSCustomObject]@{
                value = @([PSCustomObject]@{ id = 1 })
            }
        }
        if ($Uri -match '/wit/workitems') {
            # Work-Item-Details-Endpunkt: 1 PBI ohne Parent-Relation
            return [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        id        = 1
                        fields    = [PSCustomObject]@{
                            'System.WorkItemType'           = 'Product Backlog Item'
                            'System.Title'                  = 'Dot-Source PBI'
                            'System.Tags'                   = ''
                            'System.Description'            = '<p>Dot-Source Desc</p>'
                            'Microsoft.VSTS.TCM.ReproSteps' = ''
                        }
                        Relations = $null
                    }
                )
            }
        }
        return [PSCustomObject]@{ value = @(); workItems = @() }
    }

    Mock Write-Host { }   # Reduziert Rauschen in der Testausgabe

    # Skript dot-sourcen → alle Funktionen (Build-Hierarchy, Filter-Tree, …) werden
    # im Test-Scope verfügbar gemacht.
    #
    # Hinweis: In PS 7.5+ änderte sich der Typ des -Encoding-Parameters von Out-File
    # von [FileSystemCmdletProviderEncoding] zu [System.Text.Encoding]. Das Skript
    # verwendet Out-File -Encoding UTF8, was in PS 7.5+ einen ParameterBinding-Fehler
    # auslöst. Da dieser Fehler erst nach allen Funktionsdefinitionen (~Zeile 800)
    # auftritt, sind alle zu testenden Funktionen trotzdem korrekt geladen.
    # Der Fehler wird im catch-Block ignoriert.
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'GenerateReleaseNotes_Advanced.ps1'
    try {
        . $script:ScriptPath `
            -Project      'TestProject' `
            -BuildIds     '999' `
            -Pat          'testpat' `
            -OutputPath   (Join-Path $TestDrive 'ReleaseNotes.md') `
            -TemplatePath (Join-Path $TestDrive 'Template.md')
    } catch {
        # Erwarteter Fehler in PS 7.5+: Out-File -Encoding UTF8 schlägt fehl.
        # Alle Funktionsdefinitionen oberhalb von Zeile 800 sind bereits geladen.
        Write-Host "INFO (BeforeAll): Hauptlogik des Skripts beendet wegen PS7.5-Encoding-Kompatibilitätsfehler. Alle Funktionen sind geladen." -ForegroundColor Cyan
    }
}


# ===========================================================================
Describe 'Build-Hierarchy' {

    Context 'Leere Eingabe' {
        It 'Gibt leeres Ergebnis zurück' {
            $result = @(Build-Hierarchy -WorkItems @())
            $result | Should -HaveCount 0
        }
    }

    Context 'Einzelnes Element ohne Eltern' {
        It 'Wird als Root-Element zurückgegeben' {
            $wi     = New-WI -Id 1
            $result = @(Build-Hierarchy -WorkItems @($wi))
            $result | Should -HaveCount 1
            $result[0].id | Should -Be 1
        }
    }

    Context 'Parent-Kind-Beziehung' {
        It 'Kind wird als Children des Elternteils eingeordnet' {
            $parent = New-WI -Id 1 -Type 'Feature'
            $child  = New-WI -Id 2 -Relations @((New-ParentRelation -ParentId 1))

            $result = @(Build-Hierarchy -WorkItems @($parent, $child))

            $result | Should -HaveCount 1
            $result[0].id | Should -Be 1
            @($result[0].Children) | Should -HaveCount 1
            $result[0].Children[0].id | Should -Be 2
        }

        It 'Kind mit unbekanntem Parent wird als Root behandelt' {
            $orphan = New-WI -Id 5 -Relations @((New-ParentRelation -ParentId 999))
            $result = @(Build-Hierarchy -WorkItems @($orphan))
            $result | Should -HaveCount 1
            $result[0].id | Should -Be 5
        }

        It 'Mehrere Kinder desselben Parents werden alle eingeordnet' {
            $parent = New-WI -Id 1 -Type 'Feature'
            $child1 = New-WI -Id 2 -Relations @((New-ParentRelation -ParentId 1))
            $child2 = New-WI -Id 3 -Relations @((New-ParentRelation -ParentId 1))

            $result = @(Build-Hierarchy -WorkItems @($parent, $child1, $child2))

            $result | Should -HaveCount 1
            @($result[0].Children) | Should -HaveCount 2
        }
    }

    Context 'Dreistufige Hierarchie (Epic → Feature → PBI)' {
        It 'Erstellt die vollständige Kette korrekt' {
            $epic    = New-WI -Id 1 -Type 'Epic'
            $feature = New-WI -Id 2 -Type 'Feature'              -Relations @((New-ParentRelation -ParentId 1))
            $pbi     = New-WI -Id 3 -Type 'Product Backlog Item' -Relations @((New-ParentRelation -ParentId 2))

            $result = @(Build-Hierarchy -WorkItems @($epic, $feature, $pbi))

            $result | Should -HaveCount 1
            $result[0].id | Should -Be 1
            @($result[0].Children) | Should -HaveCount 1
            $result[0].Children[0].id | Should -Be 2
            @($result[0].Children[0].Children) | Should -HaveCount 1
            $result[0].Children[0].Children[0].id | Should -Be 3
        }
    }
}


# ===========================================================================
Describe 'Filter-Tree' {

    Context 'Blatt-Elemente ohne Kinder' {
        It 'Feature ohne Kinder wird entfernt' {
            $node   = New-WI -Id 1 -Type 'Feature'
            $result = @(Filter-Tree -Nodes @($node))
            $result | Should -HaveCount 0
        }

        It 'Epic ohne Kinder wird entfernt' {
            $node   = New-WI -Id 1 -Type 'Epic'
            $result = @(Filter-Tree -Nodes @($node))
            $result | Should -HaveCount 0
        }

        It 'Product Backlog Item ohne Kinder bleibt erhalten' {
            $node   = New-WI -Id 1 -Type 'Product Backlog Item'
            $result = @(Filter-Tree -Nodes @($node))
            $result | Should -HaveCount 1
        }

        It 'Bug ohne Kinder bleibt erhalten' {
            $node   = New-WI -Id 1 -Type 'Bug'
            $result = @(Filter-Tree -Nodes @($node))
            $result | Should -HaveCount 1
        }
    }

    Context 'Übergeordnete Elemente mit Kindern' {
        It 'Feature mit PBI-Kind bleibt erhalten' {
            $pbi     = New-WI -Id 2 -Type 'Product Backlog Item'
            $feature = New-WI -Id 1 -Type 'Feature' -Children @($pbi)
            $result  = @(Filter-Tree -Nodes @($feature))
            $result | Should -HaveCount 1
            $result[0].id | Should -Be 1
        }

        It 'Epic mit Feature (das PBI-Kind hat) bleibt erhalten' {
            $pbi     = New-WI -Id 3 -Type 'Product Backlog Item'
            $feature = New-WI -Id 2 -Type 'Feature' -Children @($pbi)
            $epic    = New-WI -Id 1 -Type 'Epic'    -Children @($feature)
            $result  = @(Filter-Tree -Nodes @($epic))
            $result | Should -HaveCount 1
        }
    }

    Context 'Kaskadierendes Entfernen' {
        It 'Feature ohne Kinder wird entfernt → Epic verliert sein Kind → wird ebenfalls entfernt' {
            $emptyFeature = New-WI -Id 2 -Type 'Feature'
            $epic         = New-WI -Id 1 -Type 'Epic' -Children @($emptyFeature)
            $result       = @(Filter-Tree -Nodes @($epic))
            $result | Should -HaveCount 0
        }

        It 'Gemischte Liste: leere Features werden entfernt, volle behalten' {
            $pbi          = New-WI -Id 3 -Type 'Product Backlog Item'
            $fullFeature  = New-WI -Id 2 -Type 'Feature' -Children @($pbi)
            $emptyFeature = New-WI -Id 4 -Type 'Feature'
            $result       = @(Filter-Tree -Nodes @($fullFeature, $emptyFeature))
            $result | Should -HaveCount 1
            $result[0].id | Should -Be 2
        }
    }
}


# ===========================================================================
Describe 'Format-ReleaseNotes (Markdown)' {

    Context 'Überschriften-Tiefe nach Work Item Typ' {
        It 'Epic → Überschrift 2 (##)' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 1 -Type 'Epic' -Title 'E')) -ServerUrl '' -Project 'P'
            $result | Should -Match '^## '
        }

        It 'Feature → Überschrift 3 (###)' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 2 -Type 'Feature' -Title 'F')) -ServerUrl '' -Project 'P'
            $result | Should -Match '^### '
        }

        It 'Product Backlog Item → Überschrift 4 (####)' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 3 -Type 'Product Backlog Item' -Title 'P')) -ServerUrl '' -Project 'P'
            $result | Should -Match '^#### '
        }

        It 'Bug → Überschrift 5 (#####)' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 4 -Type 'Bug' -Title 'B')) -ServerUrl '' -Project 'P'
            $result | Should -Match '^##### '
        }
    }

    Context 'Titel und ID in der Überschrift' {
        It 'Titel erscheint in der Ausgabe' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 1 -Type 'Feature' -Title 'Mein Feature')) -ServerUrl '' -Project 'P'
            $result | Should -Match 'Mein Feature'
        }

        It 'Work Item ID erscheint in Klammern' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 42 -Type 'Feature' -Title 'Test')) -ServerUrl '' -Project 'P'
            $result | Should -Match '\(42\)'
        }
    }

    Context 'Nummerierung (IncludeNumbering)' {
        It 'Keine Nummerierung wenn IncludeNumbering=$false (Standard)' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 1 -Type 'Feature' -Title 'F')) -ServerUrl '' -Project 'P' -IncludeNumbering $false
            # Überschrift sollte keine Zahl enthalten, nur Typ-Marker
            $result | Should -Match '^### '
            $result | Should -Not -Match '^### 1 '
        }

        It 'Erstes Element erhält Nummer "1" wenn IncludeNumbering=$true' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 1 -Type 'Feature' -Title 'FeatureA')) -ServerUrl '' -Project 'P' -IncludeNumbering $true
            $result | Should -Match '1 FeatureA'
        }

        It 'Zweites Element erhält Nummer "2"' {
            $items  = @((New-WI -Id 1 -Type 'Feature' -Title 'Eins'), (New-WI -Id 2 -Type 'Feature' -Title 'Zwei'))
            $result = Format-ReleaseNotes -HierarchyItems $items -ServerUrl '' -Project 'P' -IncludeNumbering $true
            $result | Should -Match '2 Zwei'
        }

        It 'Hierarchische Nummerierung (1.1) bei verschachtelten Elementen' {
            $pbi     = New-WI -Id 2 -Type 'Product Backlog Item' -Title 'KindPBI'
            $feature = New-WI -Id 1 -Type 'Feature' -Title 'FeatureA' -Children @($pbi)
            $result  = Format-ReleaseNotes -HierarchyItems @($feature) -ServerUrl '' -Project 'P' -IncludeNumbering $true
            $result  | Should -Match '1\.1 KindPBI'
        }
    }

    Context 'Präfixe für PBI und Bug' {
        It 'ItemPrefix wird vor PBI-Titel eingefügt' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 1 -Type 'Product Backlog Item' -Title 'MeinPBI')) -ServerUrl '' -Project 'P' -ItemPrefix 'US: '
            $result | Should -Match 'US: MeinPBI'
        }

        It 'BugPrefix wird vor Bug-Titel eingefügt' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 1 -Type 'Bug' -Title 'MeinBug')) -ServerUrl '' -Project 'P' -BugPrefix 'BUG: '
            $result | Should -Match 'BUG: MeinBug'
        }

        It 'ItemPrefix wird NICHT auf Features angewendet' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 1 -Type 'Feature' -Title 'FeatureX')) -ServerUrl '' -Project 'P' -ItemPrefix 'US: '
            $result | Should -Not -Match 'US: FeatureX'
        }

        It 'BugPrefix wird NICHT auf Product Backlog Items angewendet' {
            $result = Format-ReleaseNotes -HierarchyItems @((New-WI -Id 1 -Type 'Product Backlog Item' -Title 'MeinPBI')) -ServerUrl '' -Project 'P' -BugPrefix 'BUG: '
            $result | Should -Not -Match 'BUG: MeinPBI'
        }
    }

    Context 'Beschreibungen und Reproduktionsschritte' {
        It 'PBI-Beschreibung ist im Output enthalten' {
            $wi     = New-WI -Id 1 -Type 'Product Backlog Item' -Description '<p>Detail-Beschreibung</p>'
            $result = Format-ReleaseNotes -HierarchyItems @($wi) -ServerUrl '' -Project 'P'
            $result | Should -Match 'Detail-Beschreibung'
        }

        It 'Bug-ReproSteps sind im Output enthalten' {
            $wi     = New-WI -Id 1 -Type 'Bug' -ReproSteps '<ol><li>Schritt 1</li></ol>'
            $result = Format-ReleaseNotes -HierarchyItems @($wi) -ServerUrl '' -Project 'P'
            $result | Should -Match 'Schritt 1'
        }

        It 'Feature-Beschreibung erscheint wenn keine Kinder vorhanden' {
            $wi     = New-WI -Id 1 -Type 'Feature' -Description 'Standalone-Beschreibung'
            $result = Format-ReleaseNotes -HierarchyItems @($wi) -ServerUrl '' -Project 'P'
            $result | Should -Match 'Standalone-Beschreibung'
        }

        It 'Feature-Beschreibung wird NICHT ausgegeben wenn Kinder vorhanden' {
            $pbi     = New-WI -Id 2 -Type 'Product Backlog Item'
            $feature = New-WI -Id 1 -Type 'Feature' -Description 'Soll-nicht-erscheinen' -Children @($pbi)
            $result  = Format-ReleaseNotes -HierarchyItems @($feature) -ServerUrl '' -Project 'P'
            $result  | Should -Not -Match 'Soll-nicht-erscheinen'
        }
    }

    Context 'Sortierung der Kinder (PBI vor Bug)' {
        It 'Product Backlog Items erscheinen vor Bugs' {
            $bug     = New-WI -Id 2 -Type 'Bug'                  -Title 'Bug-Titel'
            $pbi     = New-WI -Id 3 -Type 'Product Backlog Item' -Title 'PBI-Titel'
            $feature = New-WI -Id 1 -Type 'Feature' -Children @($bug, $pbi)
            $result  = Format-ReleaseNotes -HierarchyItems @($feature) -ServerUrl '' -Project 'P'
            $pbiPos  = $result.IndexOf('PBI-Titel')
            $bugPos  = $result.IndexOf('Bug-Titel')
            $pbiPos | Should -BeLessThan $bugPos
        }
    }
}


# ===========================================================================
Describe 'Format-ReleaseNotesHTML' {

    Context 'HTML-Tag-Ebene nach Work Item Typ' {
        It 'Epic → <h1>' {
            $result = Format-ReleaseNotesHTML -HierarchyItems @((New-WI -Id 1 -Type 'Epic' -Title 'E')) -ServerUrl '' -Project 'P'
            $result | Should -Match '<h1'
        }

        It 'Feature → <h2>' {
            $result = Format-ReleaseNotesHTML -HierarchyItems @((New-WI -Id 2 -Type 'Feature' -Title 'F')) -ServerUrl '' -Project 'P'
            $result | Should -Match '<h2'
        }

        It 'Product Backlog Item → <h3>' {
            $result = Format-ReleaseNotesHTML -HierarchyItems @((New-WI -Id 3 -Type 'Product Backlog Item' -Title 'P')) -ServerUrl '' -Project 'P'
            $result | Should -Match '<h3'
        }

        It 'Bug → <h4>' {
            $result = Format-ReleaseNotesHTML -HierarchyItems @((New-WI -Id 4 -Type 'Bug' -Title 'B')) -ServerUrl '' -Project 'P'
            $result | Should -Match '<h4'
        }
    }

    Context 'data-custom-style Attribut (für Pandoc/Word)' {
        It 'Heading-Tags enthalten data-custom-style Attribut' {
            $result = Format-ReleaseNotesHTML -HierarchyItems @((New-WI -Id 1 -Type 'Feature' -Title 'F')) -ServerUrl '' -Project 'P'
            $result | Should -Match 'data-custom-style'
        }

        It 'Titel und ID sind im HTML enthalten' {
            $result = Format-ReleaseNotesHTML -HierarchyItems @((New-WI -Id 99 -Type 'Epic' -Title 'Mein Epic')) -ServerUrl '' -Project 'P'
            $result | Should -Match 'Mein Epic'
            $result | Should -Match '\(99\)'
        }
    }

    Context 'Nummerierung' {
        It 'Laufnummer erscheint bei IncludeNumbering=$true' {
            $result = Format-ReleaseNotesHTML -HierarchyItems @((New-WI -Id 1 -Type 'Feature' -Title 'FeatureA')) -ServerUrl '' -Project 'P' -IncludeNumbering $true
            $result | Should -Match '1 FeatureA'
        }
    }

    Context 'Beschreibungen werden ausgegeben' {
        It 'PBI-Beschreibung landet im HTML' {
            $wi     = New-WI -Id 1 -Type 'Product Backlog Item' -Description '<p>HTML-Beschreibung</p>'
            $result = Format-ReleaseNotesHTML -HierarchyItems @($wi) -ServerUrl '' -Project 'P'
            $result | Should -Match 'HTML-Beschreibung'
        }
    }
}


# ===========================================================================
Describe 'Sanitize-HtmlContent' {

    Context 'Null und leere Eingabe' {
        It 'Null-Eingabe wird unverändert zurückgegeben' {
            $result = Sanitize-HtmlContent $null
            $result | Should -BeNullOrEmpty
        }

        It 'Leerer String wird unverändert zurückgegeben' {
            $result = Sanitize-HtmlContent ''
            $result | Should -Be ''
        }
    }

    Context 'Überschriften-Tags werden zu <strong>-Absätzen' {
        It 'h<Level> wird durch p+strong ersetzt' -TestCases @(
            @{ Level = 1 }, @{ Level = 2 }, @{ Level = 3 },
            @{ Level = 4 }, @{ Level = 5 }, @{ Level = 6 }
        ) {
            param($Level)
            $result = Sanitize-HtmlContent "<h$Level>Überschrift</h$Level>"
            $result | Should -Not -Match "<h$Level"
            $result | Should -Match '<strong>'
            $result | Should -Match '</strong>'
        }

        It 'Überschrift-Tag mit Attributen wird korrekt ersetzt' {
            $result = Sanitize-HtmlContent '<h2 class="special" id="sec1">Titel</h2>'
            $result | Should -Not -Match '<h2'
            $result | Should -Match '<strong>'
        }

        It 'Resultierender Tag enthält data-custom-style="Normal"' {
            $result = Sanitize-HtmlContent '<h3>Abschnitt</h3>'
            $result | Should -Match 'data-custom-style="Normal"'
        }
    }

    Context '<p>-Tags werden normalisiert' {
        It '<p> ohne Stil erhält data-custom-style="Normal"' {
            $result = Sanitize-HtmlContent '<p>Absatztext</p>'
            $result | Should -Match 'data-custom-style="Normal"'
        }

        It '<p data-custom-style="Heading 1"> bleibt unverändert' {
            $result = Sanitize-HtmlContent '<p data-custom-style="Heading 1">Text</p>'
            $result | Should -Match 'data-custom-style="Heading 1"'
        }

        It '<p> mit anderen Attributen erhält zusätzlich Normal-Stil' {
            $result = Sanitize-HtmlContent '<p class="foo">Text</p>'
            $result | Should -Match 'data-custom-style="Normal"'
        }
    }
}


# ===========================================================================
Describe 'Embed-ImagesAsBase64' {

    Context 'Eingabe ohne DevOps-Bild-URLs' {
        It 'HTML ohne img-Tag wird unverändert zurückgegeben' {
            $html   = '<p>Kein Bild hier</p>'
            $result = Embed-ImagesAsBase64 -Html $html -Headers @{}
            $result | Should -Be $html
        }

        It 'img mit externer nicht-DevOps-URL bleibt unverändert' {
            $html   = '<img src="https://example.com/logo.png" />'
            $result = Embed-ImagesAsBase64 -Html $html -Headers @{}
            $result | Should -Be $html
        }

        It 'Null-Eingabe wird unverändert zurückgegeben' {
            $result = Embed-ImagesAsBase64 -Html $null -Headers @{}
            $result | Should -BeNullOrEmpty
        }

        It 'Leerer String wird unverändert zurückgegeben' {
            $result = Embed-ImagesAsBase64 -Html '' -Headers @{}
            $result | Should -Be ''
        }
    }

    Context 'Azure DevOps Cloud URL (dev.azure.com)' {
        BeforeEach {
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    Content = [System.Text.Encoding]::UTF8.GetBytes('FAKEIMAGEDATA')
                    Headers = @{ 'Content-Type' = 'image/png' }
                }
            }
        }

        It 'dev.azure.com URL wird als Base64 eingebettet' {
            $html   = '<img src="https://dev.azure.com/org/proj/_apis/wit/attachments/abc123" />'
            $result = Embed-ImagesAsBase64 -Html $html -Headers @{}
            $result | Should -Match 'data:image/png;base64,'
            $result | Should -Not -Match 'https://dev.azure.com'
        }
    }

    Context 'On-Premise Server-URL' {
        BeforeEach {
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    Content = [System.Text.Encoding]::UTF8.GetBytes('FAKEIMAGEDATA')
                    Headers = @{ 'Content-Type' = 'image/jpeg' }
                }
            }
        }

        It 'Konfigurierter ServerUrl wird als Bild-Quelle erkannt' {
            $html   = '<img src="http://myserver:8080/tfs/proj/_apis/attachments/xyz" />'
            $result = Embed-ImagesAsBase64 -Html $html -Headers @{} -ServerUrl 'http://myserver:8080/tfs'
            $result | Should -Match 'data:image/jpeg;base64,'
        }
    }

    Context 'Fehlerbehandlung bei fehlschlagendem Download' {
        BeforeEach {
            Mock Invoke-WebRequest { throw 'Verbindung verweigert' }
            Mock Write-Host { }
        }

        It 'Bild-URL bleibt unverändert wenn Download fehlschlägt' {
            $html   = '<img src="https://dev.azure.com/org/proj/_apis/wit/attachments/abc" />'
            $result = Embed-ImagesAsBase64 -Html $html -Headers @{}
            $result | Should -Match 'https://dev.azure.com'
            $result | Should -Not -Match 'data:image'
        }
    }
}


# ===========================================================================
Describe 'Get-WorkItemsByTags (REST-API gemockt)' {

    BeforeEach {
        $script:TestHeaders = @{ Authorization = 'Basic dGVzdDp0ZXN0' }
    }

    Context 'Keine Tags übergeben' {
        It 'Gibt sofort leeres Array zurück ohne API-Aufruf' {
            $result = @(Get-WorkItemsByTags -ServerUrl 'http://srv' -Project 'P' -ProjectDecoded 'P' -Headers $script:TestHeaders -Tags @())
            $result | Should -HaveCount 0
        }
    }

    Context 'Erfolgreich gefundene Work Items' {
        BeforeEach {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    workItems = @(
                        [PSCustomObject]@{ id = 10 },
                        [PSCustomObject]@{ id = 20 },
                        [PSCustomObject]@{ id = 30 }
                    )
                }
            }
        }

        It 'Gibt alle IDs aus der WIQL-Antwort zurück' {
            $result = @(Get-WorkItemsByTags -ServerUrl 'http://srv' -Project 'P' -ProjectDecoded 'Projekt' -Headers $script:TestHeaders -Tags @('Release'))
            $result | Should -HaveCount 3
            $result | Should -Contain 10
            $result | Should -Contain 20
            $result | Should -Contain 30
        }
    }

    Context 'Keine Treffer in der WIQL-Antwort' {
        BeforeEach {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{ workItems = @() }
            }
        }

        It 'Gibt leeres Array zurück wenn keine Work Items gefunden' {
            $result = @(Get-WorkItemsByTags -ServerUrl 'http://srv' -Project 'P' -ProjectDecoded 'P' -Headers $script:TestHeaders -Tags @('NichtVorhanden'))
            $result | Should -HaveCount 0
        }
    }

    Context 'API-Fehler (Netzwerkausfall)' {
        BeforeEach {
            Mock Invoke-RestMethod { throw [System.Net.WebException]'Verbindung abgelehnt' }
            Mock Write-Error { }
        }

        It 'Gibt leeres Array zurück statt Exception zu werfen' {
            { Get-WorkItemsByTags -ServerUrl 'http://srv' -Project 'P' -ProjectDecoded 'P' -Headers $script:TestHeaders -Tags @('Release') } | Should -Not -Throw
            $result = @(Get-WorkItemsByTags -ServerUrl 'http://srv' -Project 'P' -ProjectDecoded 'P' -Headers $script:TestHeaders -Tags @('Release'))
            $result | Should -HaveCount 0
        }
    }
}


# ===========================================================================
Describe 'Get-WorkItemDetails (REST-API gemockt)' {

    BeforeEach {
        $script:TestHeaders = @{ Authorization = 'Basic dGVzdDp0ZXN0' }
    }

    Context 'Leeres IDs-Array' {
        It 'Gibt $null zurück ohne API-Aufruf' {
            $result = Get-WorkItemDetails -Ids @() -ServerUrl 'http://srv' -Project 'P' -Headers $script:TestHeaders
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Erfolgreicher API-Aufruf' {
        BeforeEach {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            id     = 42
                            fields = [PSCustomObject]@{
                                'System.Title'        = 'Wichtiges Feature'
                                'System.WorkItemType' = 'Bug'
                            }
                        }
                    )
                }
            }
        }

        It 'Gibt Work Item mit korrekter ID zurück' {
            $result = Get-WorkItemDetails -Ids @(42) -ServerUrl 'http://srv' -Project 'P' -Headers $script:TestHeaders
            @($result) | Should -HaveCount 1
            $result[0].id | Should -Be 42
        }

        It 'Work Item Typ wird korrekt übermittelt' {
            $result = Get-WorkItemDetails -Ids @(42) -ServerUrl 'http://srv' -Project 'P' -Headers $script:TestHeaders
            $result[0].fields.'System.WorkItemType' | Should -Be 'Bug'
        }

        It 'Work Item Titel wird korrekt übermittelt' {
            $result = Get-WorkItemDetails -Ids @(42) -ServerUrl 'http://srv' -Project 'P' -Headers $script:TestHeaders
            $result[0].fields.'System.Title' | Should -Be 'Wichtiges Feature'
        }
    }

    Context 'API-Fehler (Server nicht erreichbar)' {
        BeforeEach {
            Mock Invoke-RestMethod { throw [System.Net.WebException]'Timeout' }
            Mock Write-Error { }
        }

        It 'Gibt $null zurück bei API-Fehler' {
            $result = Get-WorkItemDetails -Ids @(1) -ServerUrl 'http://srv' -Project 'P' -Headers $script:TestHeaders
            $result | Should -BeNullOrEmpty
        }
    }
}
