enum DnsRecordType {
    SOA
    NS
    A
    AAAA
    CAA
    CNAME
    MX
    SRV
    TXT
}

function Show-Route53Dns
{
    [Alias('dns_show')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [string]
        $ZoneId,

        [Parameter()]
        [ValidateSet('FQDN', 'Relative')]
        [string]
        $NameFormat = 'FQDN',

        [Parameter()]
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [ValidateSet('Type', $null)]
        [string]
        $GroupBy,

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_zone_id          = $ZoneId
    $_name_format      = $NameFormat
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_select_definition = @{

        IsAlias = {
            New-Checkbox -PlainText:$_plain_text ($_.AliasTarget -as [bool])
        }
        Name = {
            if ($_name_format -eq 'Relative'){
                $_name = $_.Name -replace $_zone.Name
                $_name -eq '' ? '@': $_name -replace '.$'
            }
            else {
                $_.Name
            }
        }
        Routing = {
            $_.Weight `
                ? 'Weighted' `
                : $_.GeoLocation `
                    ? 'Geolocation' `
                    : $_.Failover `
                        ? 'Failover' `
                        : $_.MultiValueAnswer `
                            ? 'Multivalue answer' `
                            : $_.CidrRoutingConfig `
                                ? 'IP-based' `
                                : $_.Region `
                                    ? 'Latency' `
                                    : 'Simple'
        }
        TTL = {
            $_.TTL ? (New-NumberInfo $_.TTL) : $null
        }
        Type = {
            $_.Type.Value -as [DnsRecordType]
        }
        Value = {
            $_value = $_.AliasTarget `
                ? $_.AliasTarget.DNSName `
                : ($_.ResourceRecords | Select-Object -ExpandProperty Value)

            if ($_.Type -eq 'SOA') {
                $_tokens             = $_value -split '\s+'
                $_primary_nameserver = $_tokens[0]
                $_admin_contact      = $_tokens[1]
                $_serial             = $_tokens[2]
                $_refresh            = $_tokens[3]
                $_retry              = $_tokens[4]
                $_expire             = $_tokens[5]
                $_minimum            = $_tokens[6]

                $_align = $_tokens[2..6] | Measure-Object -Property Length -Maximum | Select-Object -ExpandProperty Maximum

                "{0} {1} (" -f $_primary_nameserver, $_admin_contact
                "  {0,-$($_align)} ; Serial number" -f $_serial
                "  {0,-$($_align)} ; Refresh" -f $_refresh
                "  {0,-$($_align)} ; Retry" -f $_retry
                "  {0,-$($_align)} ; Expire" -f $_expire
                "  {0,-$($_align)} ; Minimum TTL )" -f $_minimum
            }
            else {
                $_value
            }
        }
    }

    $_view_definition = @{
        Default = @(
            'Type', 'Name', 'Value', 'TTL', 'IsAlias', 'Routing'
        )
    }

    # Apply default sort order.
    if (
        $_group_by -eq 'Zone' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1, 2) # => Sort by Name, RouteTableId
    }

    # Prepare a list to hold all DNS records.
    $_dns_list = [System.Collections.Generic.List[Amazon.Route53.Model.ResourceRecordSet]]::new()

    # Check if the hosted zone exists.
    try {
        $_zone = Get-R53HostedZone -Verbose:$false $_zone_id | Select-Object -ExpandProperty HostedZone
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    try {
        $_next_record_type = $null
        $_next_record_name = $null
        $_next_record_id   = $null

        do {
            $_response = Get-R53ResourceRecordSet -Verbose:$false $_zone_id `
                -StartRecordName $_next_record_name `
                -StartRecordType $_next_record_type `
                -StartRecordIdentifier $_next_record_id

            $_this_batch = $_response.ResourceRecordSets
            foreach ($_record in $_this_batch) {
                $_record | Add-Member -NotePropertyName 'ZoneId' -NotePropertyValue $_zone.Id
            }
            $_dns_list.AddRange($_this_batch)

            $_next_record_type = $_response.NextRecordType
            $_next_record_name = $_response.NextRecordName
            $_next_record_id   = $_response.NextRecordIdentifier

        } while ($_response.IsTruncated)
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_dns_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}