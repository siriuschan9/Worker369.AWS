function Show-Fleet
{
    [CmdletBinding()]
    [Alias('fleet_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Status', 'PatchCompliance')]
        [string]
        $View = 'Status',

        [ValidateSet('PlatformType', 'PingStatus', 'InstanceStatus', $null)]
        [string]
        $GroupBy = 'PlatformType',

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
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up later.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    $_view_definition = @{
        Status = @(
            'InstanceId', 'Name', 'ComputerName', 'IpAddress', 'PlatformName', 'PlatformVersion',
            'InstanceStatus', 'PingStatus'
        )
        PatchCompliance = @(
            'InstanceId', 'Name', 'ComputerName', 'PatchBaseline', 'PatchGroup',
            'ComplianceStatus', 'NonCompliantCount'
        )
    }

    $_select_definition = @{
        AgentVersion = {
            $_is_latest = $_.IsLatestVersion
            $_agent_version = $_.AgentVersion
            New-Checkbox -PlainText:$_plain_text -Description $_agent_version $_is_latest
        }
        CompliantCount = {
            $_compliance_data = $_compliance_lookup[$_.InstanceId]
            New-NumberInfo ($_compliance_data ? $_compliance_data.CompliantSummary[0].CompliantCount : -1)
        }
        ComputerName = {
            $_.ComputerName
        }
        ComplianceStatus = {
            $_status = $_compliance_lookup[$_.InstanceId].Status ?? 'NO_DATA'
            $_is_compliant = $_status -eq 'COMPLIANT'
            New-Checkbox -PlainText:$_plain_text -Description $_status $_is_compliant
        }
        InstanceId = {
            $_.InstanceId
        }
        InstanceStatus = {
            $_instance_status = $_.InstanceStatus
            New-Checkbox -PlainText:$_plain_text -Description $_instance_status $($_instance_status -eq 'Active')
        }
        IpAddress = {
            New-IPv4Address $_.IpAddress
        }
        Name = {
            $_ec2_lookup[$_.InstanceId].Name
        }
        NonCompliantCount = {
            $_compliance_data = $_compliance_lookup[$_.InstanceId]
            New-NumberInfo ($_compliance_data ? $_compliance_data.NonCompliantSummary[0].NonCompliantCount : -1)
        }
        PatchBaseline = {
            $_patch_group_name  = $_ec2_lookup[$_.InstanceId].PatchGroup
            $_patch_group       = $_patch_group_lookup[$_patch_group_name]
            $_patch_baseline_id = $_patch_group.BaselineIdentity.BaselineId

            $_patch_baseline = $_patch_baseline_lookup[$_patch_baseline_id]
            $_patch_baseline | Get-ResourceString `
                -PlainText:$_plain_text -IdPropertyName BaselineId -NamePropertyName BaselineName
        }
        PatchGroup = {
            $_ec2_lookup[$_.InstanceId].PatchGroup
        }
        PlatformName = {
            $_.PlatformName
        }
        PlatformVersion = {
            $_.PlatformVersion
        }
        PlatformType = {
            $_.PlatformType
        }
        PingStatus = {
            $_ping_status = $_fleet_lookup[$_.InstanceId].PingStatus
            New-Checkbox -PlainText:$_plain_text -Description $_ping_status $($_ping_status -eq 'Online')
        }
    }

    # We use a separate project definition because we want to do additional formatting after the sorting.
    $_project_definition = @{
        AgentVersion = {
            $_.AgentVersion
        }
        CompliantCount = {
            $_.CompliantCount
        }
        ComputerName = {
            $_.ComputerName
        }
        ComplianceStatus = {
            if ($_.ComplianceStatus.Description -eq 'NON_COMPLIANT' -and -not $_plain_text) {
                "$($PSStyle.Background.BrightRed)" +
                "$(New-Checkbox -Description 'NON_COMPLIANT' $false -PlainText:$true)" +
                "$($PSStyle.Reset)"
            }
            else {
                "$($_.ComplianceStatus)"
            }
        }
        InstanceId = {
            $_.InstanceId
        }
        InstanceStatus = {
            $_.InstanceStatus
        }
        IpAddress = {
            $_.IpAddress
        }
        Name = {
            $_.Name
        }
        NonCompliantCount = {
            $_.NonCompliantCount
        }
        PatchBaseline = {
            $_.PatchBaseline
        }
        PatchGroup = {
            $_.PatchGroup
        }
        PlatformName = {
            $_.PlatformName
        }
        PlatformVersion = {
            $_.PlatformVersion
        }
        PlatformType = {
            $_.PlatformType
        }
        PingStatus = {
            $_.PingStatus
        }
    }

    try {
        # We use SSM inventory because only this returned data contains stopped instances.
        Write-Message -Progress $_cmdlet_name 'Retrieving SSM Inventory.'
        $_inventory = Get-SSMInventory -Verbose -Filter @{
            Key    = 'AWS:InstanceInformation.InstanceStatus'
            Values = 'Terminated'
            Type   = 'NotEqual'
        } | ForEach-Object {
            $_attribute_dict = $_.Data['AWS:InstanceInformation'].Content[0]
            [PSCustomObject]::new($_attribute_dict -as [hashtable])
        }

        # We just be the name & PatchGroup tag of the EC2 instances.
        Write-Message -Progress $_cmdlet_name 'Retrieving EC2 Instances.'
        $_ec2_lookup = Get-EC2Instance -Verbose:$false `
            | Select-Object -ExpandProperty Instances `
            | Select-Object `
                InstanceId,
                @{
                    Name = 'Name';
                    Expression = {$_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value}
                },
                @{
                    Name = 'PatchGroup';
                    Expression = {$_.Tags | Where-Object Key -eq 'PatchGroup' | Select-Object -ExpandProperty Value}
                }
            | Group-Object -AsHashTable InstanceId

        if ($_view -in @('Status')) {
            # This is to get the PingStatus of the instance.
            Write-Message -Progress $_cmdlet_name 'Retrieving SSM Fleet Instances.'
            $_fleet_lookup = Get-SSMInstanceInformation -Verbose:$false | Group-Object InstanceId -AsHashTable
        }

        if ($_view -in @('PatchCompliance')) {
            Write-Message -Progress $_cmdlet_name 'Retrieving Patch Compliance Data.'

            $_compliance_lookup = Get-SSMResourceComplianceSummaryList -Verbose:$false -Filter @{
                Key    = 'ComplianceType'
                Values = 'Patch'
                Type   = 'Equal'
            } | Group-Object -AsHashTable ResourceId

            $_patch_baseline_lookup = Get-SSMPatchBaseline -Verbose:$false | Group-Object -AsHashTable BaselineId
            $_patch_group_lookup    = Get-SSMPatchGroup -Verbose:$false | Group-Object -AsHashTable PatchGroup
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Apply default sort order.
    if (
        $_view -eq 'Status' -and
        $_group_by -eq 'PlatformType' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 1) # => Sort by ComputerName, InstanceId
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    $_project_list_extended = $_project_list | ForEach-Object {
        @{
            Name       = "$_"
            Expression = $_project_definition[$_]
        }
    }

    # Generate output after sorting and exclusion.
    $_output = $_inventory `
        | Select-Object $_select_list `
        | Sort-Object $_sort_list `
        | Select-Object $_project_list_extended

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -AlignLeft PingStatus, InstanceStatus, AgentVersion, ComplianceStatus `
            -GroupBy $_group_by `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator
    }
}