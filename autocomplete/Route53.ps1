$_cmd_lookup = @{
    ZoneId = @(
        'Show-Route53Dns'
    )
}

# ZoneId
Register-ArgumentCompleter -ParameterName 'ZoneId' -CommandName $_cmd_lookup['ZoneId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_dim   = [System.Management.Automation.PSStyle]::Instance.Dim
    $_reset = [System.Management.Automation.PSStyle]::Instance.Reset

    $_zone_list = Get-R53HostedZoneList -Verbose:$false | Where-Object {
        $_.Id -like "$($_word_to_complete)*"
    }

    if (-not $_zone_list) { return }

    $_align = $_zone_list.Id |
        Select-Object -ExpandProperty Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum


    $_zone_list | ForEach-Object {

        $_display_item = "{0, -$($_align)} {1}" -f $_.Id, "$($_dim)| $($_.Name)$($_reset)"

        [System.Management.Automation.CompletionResult]::new(
            $_.Id,            # completionText
            $_display_item,   # listItemText
            'ParameterValue', # resultType
            $_display_item    # toolTip
        )
    }
}