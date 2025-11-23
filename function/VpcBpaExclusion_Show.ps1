function Show-VpcBpaExclusion
{
    [Alias('vpc_bpa_excl_show')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [Parameter()]
        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [Parameter()]
        [ValidateSet('InternetGatewayBlockMode', 'ExclusionMode', 'Status', $null)]
        [string]
        $GroupBy = 'InternetGatewayBlockMode',

        [Parameter()]
        [switch]
        $ActiveStatusOnly,

        [Parameter()]
        [Int[]]
        $Sort,

        [Parameter()]
        [Int[]]
        $Exclude,

        [Parameter()]
        [switch]
        $PlainText,

        [Parameter()]
        [switch]
        $NoRowSeparator
    )

    BEGIN
    {
        $_view_definition = @{
            Default = @('ExclusionId', 'Resource', 'ExclusionMode', 'Status', 'Reason', 'CreationDate', 'DeletionDate')
        }

        $_select_definition = @{

            CreationDate = { $_.CreationTimestamp }

            DeletionDate = { $_.DeletionTimestamp -eq [datetime]::MinValue ? $null : $_.DeletionTimestamp }

            ExclusionId = { $_.ExclusionId }

            ExclusionMode = { $_.InternetGatewayExclusionMode }

            InternetGatewayBlockMode = { $_igw_block_mode }

            Status = {
                $_state   = $_.State -in @('create-complete', 'update-complete') ? 'active' : $_.State
                $_checked = $_state -eq 'active'

                New-Checkbox -Description $_state -PlainText:$_plain_text $_checked
            }

            Reason = { $_.Reason }

            Resource = {
                $_vpc_id = $_.ResourceArn -replace '^arn:aws:ec2:[0-9a-z-]+:\d{12}:vpc\/'

                $_vpc_lookup[$_vpc_id] | Get-ResourceString `
                    -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
        }
    }

    PROCESS
    {
        # Use snake_case.
        $_view             = $View
        $_filter           = $Filter
        $_active_only      = $ActiveStatusOnly
        $_group_by         = $GroupBy
        $_sort             = $Sort
        $_exclude          = $Exclude
        $_plain_text       = $PlainText.IsPresent
        $_no_row_separator = $NoRowSeparator.IsPresent

        # Apply default sort order.
        if (
            $_group_by -eq 'InternetGatewayBlockMode' -and
            -not $PSBoundParameters.Keys.Contains('Exclude') -and
            -not $PSBoundParameters.Keys.Contains('Sort')
        ) {
            $_sort = @(-4, 2) # Sort by Status, Resource | See $_view_definition in BEGIN block.
        }

        # Define Filter for exclusions in Active State only.
        $_active_filter = @{Name = 'state'; Values = @('create-complete', 'update-complete')}

        # Add Active-State exclusions to filter.
        if ($_active_only)
        {
            $_filter = $_filter ? $_filter + $_active_filter : $_active_filter
        }

        try {
            # Query the Internet Gateway Block Mode
            $_igw_block_mode = Get-EC2VpcBlockPublicAccessOption -Verbose:$false `
                -Select VpcBlockPublicAccessOptions.InternetGatewayBlockMode `

            # Query the BPA exclusions.
            $_excl_list = Get-EC2VpcBlockPublicAccessExclusion -Verbose:$false -Filter $_filter -MaxResult 1000

            if ($_excl_list)
            {
                $_vpc_id_list = $_excl_list.ResourceArn -replace '^arn:aws:ec2:[0-9a-z-]+:\d{12}:vpc\/'
                $_vpc_lookup  = Get-EC2Vpc -Verbose:$false -Filter @{
                    Name   = 'vpc-id';
                    Values = $_vpc_id_list
                } | Group-Object -AsHashTable VpcId
            }
        }
        catch{
            # Remove caught exception emitted into $Error list to prevent duplicates when we report the error.
            Pop-ErrorRecord $_

            # Re-throw caught exception. This will write back the same error to the $Error list.
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

        # Print out the BPA exclusions.
        $_excl_list                  |
        Select-Object $_select_list  |
        Sort-Object   $_sort_list    |
        Select-Object $_project_list |
        Format-Column `
            -GroupBy $_group_by -AlignLeft Status -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}

<#
# [Amazon.EC2.VpcBlockPublicAccessExclusionState].GetFields() | ForEach-Object {
#   $_.GetValue($null).Value
# }
# create-complete | create-failed | create-in-progress | delete-complete | delete-in-progress |
# disable-complete | disable-in-progress | update-complete | update-failed | update-in-progress
#>