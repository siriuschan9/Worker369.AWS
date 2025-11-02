using namespace System.Management.Automation

$_cmd_lookup = @{

    ResourceScanId = @(
        'Show-IacScanBrief', 'Show-IacScanDetail'
    )
}

# RegisterScanId
Register-ArgumentCompleter -ParameterName 'ResourceScanId' -CommandName $_cmd_lookup['ResourceScanId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_scan_list = Get-CFNResourceScanList -Verbose:$false

    if (-not $_scan_list) { return }

    $_dim   = [PSStyle]::Instance.Dim
    $_reset = [PSStyle]::Instance.Reset

    $_align = `
        $_scan_list.ResourceScanId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_scan_list | Sort-Object StartTime -Descending |
    Where-Object ResourceScanId -Like "$_word_to_complete*" | ForEach-Object {

        $_hint = "{0, -$_align} $_dim| {1}$_reset" -f $_.ResourceScanId, $_.StartTime

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceScanId, # completionText
            $_hint ,           # listItemText
            'ParameterValue',  # resultType
            $_                 # toolTip
        )
    }
}