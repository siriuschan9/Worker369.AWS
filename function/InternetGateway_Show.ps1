using namespace System.Collections.Generic
using namespace Amazon.EC2.Model

function Show-InternetGateway
{
    [Alias('igw_show')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [Parameter()]
        [Amazon.EC2.Model.Filter[]]
        $Filter,

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

    # Use snake_case.
    $_view             = $View
    $_filter           = $Filter
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plaintext        = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_select_definition = @{
        InternetGatewayId = {
            $_.InternetGatewayId
        }
        Name = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        AttachedToVpc = {
            $_vpc_lookup[$_.InternetGatewayId] | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plaintext
        }
    }

    $_view_definition = @{
        Default = @('InternetGatewayId', 'Name', 'AttachedToVpc')
    }

    # Apply default sort order.
    if (
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 1) # => Sort by Name, InternetGatewayId
    }

    try {
        # Retrieve IGWs.
        $_igw_list = Get-EC2InternetGateway -Filter $_filter -Verbose:$false

        # Retrieve VPCs.
        $_vpc_ht = Get-EC2Vpc -Verbose:$false -Filter @{
            Name   ='vpc-id'
            Values = $_igw_list.Attachments.VpcId
        } | Group-Object -AsHashTable VpcId

        # Create a VPC lookup table to lookup by IGW ID.
        $_vpc_lookup = [hashtable]::new()

        foreach($_igw in $_igw_list)
        {
            $_vpc_id = $_igw.Attachments.VpcId

            if (-not [string]::IsNullOrEmpty(($_vpc_id)))
            {
                $_vpc_lookup.Add($_igw.InternetGatewayId, $_vpc_ht[$_vpc_id])
            }
        }

    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Exit early if there are not internet gateway to show.
    if(-not $_igw_list) { return }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Print out the summary table.
    $_igw_list                   |
    Select-Object $_select_list  |
    Sort-Object   $_sort_list    |
    Select-Object $_project_list |
    Format-Column -PlainText:$_plaintext -NoRowSeparator:$_no_row_separator
}