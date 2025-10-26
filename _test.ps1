
$to_load         = Import-PowerShellDataFile ./data/_to_load.psd1
$loaded_commands = Get-Command -Module Worker369.AWS | Select-Object -ExpandProperty Name

$expected_commands = $to_load | Select-Object -ExpandProperty Commands
$expected_commands | ForEach-Object {

    [PSCustomObject]@{
        Command = $_
        Verb    = ($_ -split '-')[0]
        Noun    = ($_ -split '-')[1]
        Loaded  = $loaded_commands -contains $_
    }
} | Sort-Object Noun | Format-Table Noun, Verb, Command, Loaded

$expected_aliases = $to_load | Select-Object -ExpandProperty Aliases
$expected_aliases | ForEach-Object {

    $alias = $null
    $alias = Get-Alias $_ -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Alias   = $_
        Command = $alias.Definition
        Loaded = $null -ne $alias
    }
} | Format-Table