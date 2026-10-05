function Show-SsmCommandOutput
{
    [CmdletBinding()]
    [Alias('ssm_cmd_output_show')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}')]
        [string]
        $CommandId,

        [Parameter(Position = 1)]
        [ValidatePattern('^i-([0-9a-f]{8}|[0-9a-f]{17})$')]
        [string]
        $InstanceId,

        [ValidateSet('Status', 'CommandId', $null)]
        [string]
        $GroupBy = 'CommandId',

        [int[]]
        $Sort,

        [int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_command_id       = $CommandId
    $_instance_id      = $InstanceId
    $_view             = 'Default'
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up later.
    $_cmdlet_name  = $PSCmdlet.MyInvocation.MyCommand.Name

    $_view_definition = @{
        Default = @(
            'InstanceId', 'ComputerName', 'Status', 'StandardOutput', 'StandardError'
        )
    }

    $_select_definition = @{
        CommandId = {
            $_.CommandId
        }
        ComputerName = {
            $_inventory_lookup[$_.InstanceId].ComputerName
        }
        InstanceId = {
            $_.InstanceId
        }
        StandardError = {
            # We need to replace carriage return with new line.
            # Then replace the double new line with single new line.
            # We cannot replace \r\n with \n in single replace operation - It does not work.
            # It has too be two replacements.
            $_.StandardErrorContent.Trim() -replace "`r", "`n" -replace "`n`n", "`n" -split "`n"
        }
        StandardOutput = {
            # We need to replace carriage return with new line.
            # Then replace the double new line with single new line.
            # We cannot replace \r\n with \n in single replace operation - It does not work.
            # It has too be two replacements.
            $_.StandardOutputContent.Trim() -replace "`r", "`n" -replace "`n`n", "`n" -split "`n"
        }
        Status = {
            $_status = $_.Status.Value
            New-Checkbox -PlainText:$_plain_text -Description $_status ($_status -eq 'Success')
        }
    }

    # We use splatting cos we want to dynamically add InstanceId if it is specified from the caller.
    $_params = @{Verbose = $false; CommandId = $_command_id}

    # Add InstanceId only if it has been specified by the caller.
    if ($PSBoundParameters.ContainsKey('InstanceId')) { $_params['InstanceId'] = $_instance_id }

    try {
        # We list out the invocations, but we will only need the list of Instance ID for this API.
        Write-Message -Progress $_cmdlet_name 'Fetching Command Invocations.'
        $_instance_id_list = Get-SSMCommandInvocation @_params | Select-Object -ExpandProperty InstanceId

        # Exit early if there are not invocations.
        if (-not $_instance_id_list) { return }

        # We use SSM inventory because it can return stopped instances.
        Write-Message -Progress $_cmdlet_name 'Fetching SSM Inventory.'
        $_inventory_lookup = Get-SSMInventory -Verbose:$false -Filter @{
            Key    = 'AWS:InstanceInformation.InstanceId'
            Values = $_instance_id_list
            Type   = 'Equal'
        } | ForEach-Object {
            $_attribute_dict = $_.Data['AWS:InstanceInformation'].Content[0]
            [PSCustomObject]($_attribute_dict -as [hashtable])
        } | Group-Object -AsHashTable InstanceId

        # Now, we fetch the invocation details for each instance.
        Write-Message -Progress $_cmdlet_name 'Fetching Invocation Details.'
        $_invocation_detail_list = $_instance_id_list | ForEach-Object {
            Get-SSMCommandInvocationDetail -Verbose:$false -CommandId $_command_id -InstanceId $_
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
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
    $_output = $_invocation_detail_list `
        | Select-Object $_select_list `
        | Sort-Object $_sort_list `
        | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -AlignLeft Status `
            -GroupBy $_group_by `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator
    }
}