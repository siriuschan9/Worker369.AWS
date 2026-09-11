function Show-TransitGatewayRouteTable
{
    [Alias('tgw_rt_show')]
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [parameter(Position = 0)]
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [Parameter(ParameterSetName = 'TransitGatewayId')]
        [ValidatePattern('^vpc-[0-9a-f]{17}$')]
        [string[]]
        $TransitGatewayId,

        [Parameter(ParameterSetName = 'TransitGatewayId')]
        [string]
        $TransitGatewayName,

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('TransitGateway', $null)]
        [string]
        $GroupBy = 'TransitGateway',

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
    $_filter           = $Filter
    $_tgw_id           = $TransitgatewayId
    $_tgw_name         = $TransitGatewayName
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_select_definition = @{
        TransitGatewayRouteTableId = {
            $_.TransitGatewayRouteTableId
        }
        Name = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        TransitGateway = {
            $_tgw_lookup[$_.TransitGatewayId] | `
                Get-ResourceString -IdPropertyName 'TransitGatewayId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        IsDefaultAssoc = {
            New-Checkbox -PlainText:$_plain_text $_.DefaultAssociationRouteTable
        }
        isDefaultProp = {
            New-Checkbox -PlainText:$_plain_text $_.DefaultPropagationRouteTable
        }
        AssociationVpc = {
            $_assoc_lookup[$_.TransitGatewayRouteTableId] | ForEach-Object {

                # Account ID portion - If this VPC is in this account, we display the AWS Account ID using "."
                $_account_id     = $_attach_lookup[$_.TransitGatewayAttachmentId].ResourceOwnerId
                $_format_account = $_account_id -eq $_this_account ? '           .' : $_account_id

                # VPC portion
                $_vpc_id = $_.ResourceId
                if ($_vpc = ($_vpc_lookup[$_vpc_id])) {         
                    $_format_vpc = $_vpc | 
                        Get-ResourceString -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text 
                }
                else {                                          
                    $_format_vpc = $_vpc_id                     
                }
                
                # Eg. 999988887777 | vpc-111122223333
                "$($_format_account) | $($_format_vpc)"
            } | Sort-Object
        }
        PropagationVpc = {
            $_prog_lookup[$_.TransitGatewayRouteTableId] | ForEach-Object {

                # Account ID portion - If this VPC is in this account, we display the AWS Account ID using "."
                $_account_id     = $_attach_lookup[$_.TransitGatewayAttachmentId].ResourceOwnerId
                $_format_account = $_account_id -eq $_this_account ? '           .' : $_account_id

                # VPC portion
                $_vpc_id = $_.ResourceId
                if ($_vpc = ($_vpc_lookup[$_vpc_id])) {         
                    $_format_vpc = $_vpc | 
                        Get-ResourceString -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text 
                }
                else {                                          
                    $_format_vpc = $_vpc_id                     
                }

                # Eg. 999988887777 | vpc-111122223333
                "$($_format_account) | $($_format_vpc)"
            } | Sort-Object
        }
    }

    $_view_definition = @{
        Default = @(
            'TransitGateway', 'TransitGatewayRouteTableId', 'Name', 
            'AssociationVpc', 'PropagationVpc', 'IsDefaultAssoc', 'IsDefaultProp'
        )
    }
    
    # Apply default sort order.
    if (
        $_group_by -eq 'TransitGateway' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 1) # => Sort by Name, TransitGatewayRouteTableId
    }

    try {
        # Save a copy of this account ID
        $_this_account = Get-STSCallerIdentity | Select-Object -ExpandProperty Account

        # Initialize a filter list.
        $_filter_list = [System.Collections.Generic.List[Filter]]::new()

        # Add elements in the -Filter parameter to the filter list.
        $_filter.ForEach({
            $_filter_list.Add($_)
        })

        # Add the -TransitGatewayId parameter to the filter list.
        if (-not [string]::IsNullOrEmpty($_tgw_id))
        {
            $_filter_list.Add([Amazon.EC2.Model.Filter]@{
                Name   = 'transit-gateway-id'
                Values = $_tgw_id
            })
        }

        # Find out the Transit Gateway ID from the -TransitGatewayName parameter.
        if (-not [string]::IsNullOrEmpty($_vpc_name))
        {
            $_tgw_id_filter = Get-EC2TransitGateway -Verbose:$false `
                -Select TransitGateways.TransitGatewayId -Filter @{Name = 'tag:Name'; Values = $_tgw_name}

            # Add a tgw-id filter to the filter list.
            if ($_tgw_id_filter)
            {
                $_tgw_filter = [Amazon.EC2.Model.Filter]@{
                    Name   = 'transit-gateway-id';
                    Values = $_tgw_id_filter
                }
                $_filter_list.Add($_tgw_filter)
            }
        }

        # Query TGW Route Tables. Save to list.
        $_trt_list = Get-EC2TransitGatewayRouteTable -Verbose:$false -Filter $($_filter_list.Count -eq 0 ? $null : $_filter_list)

        # Exit early if there are no tgw route tebles to show.
        if (-not $_trt_list) { return }
        
        $_tgw_id_list = $_trt_list | Select-Object -Unique -ExpandProperty TransitGatewayId

        # Query TGW
        $_tgw_lookup = Get-EC2TransitGateway -Verbose:$false ` -Filter @{
            Name   = 'transit-gateway-id'
            Values = $_tgw_id_list
        } | Group-Object -AsHashTable TransitGatewayId

        # Query Associations. Save to hashtable.
        $_assoc_lookup = @{}
        $_trt_list | ForEach-Object { 
            $_assoc_lookup[$_.TransitGatewayRouteTableId] = `
                Get-EC2TransitGatewayRouteTableAssociation -Verbose:$false `
                -TransitGatewayRouteTableId $_.TransitGatewayRouteTableId
        }

        # Query Propagations. Save to hashtable.
        $_prog_lookup = @{}
        $_trt_list | ForEach-Object { 
            $_prog_lookup[$_.TransitGatewayRouteTableId] = `
                Get-EC2TransitGatewayRouteTablePropagation -Verbose:$false `
                -TransitGatewayRouteTableId $_.TransitGatewayRouteTableId
        }

        # Query Attachments. Save to hashtable.
        $_attach_lookup = Get-EC2TransitGatewayAttachment -Verbose:$false -Filter @{
            Name   = 'transit-gateway-id'; 
            Values = $_tgw_id_list
        } | Group-Object -AsHashTable TransitGatewayAttachmentId

        # Query VPC. Save to hashtable.
        $_vpc_lookup = (Get-EC2Vpc -Verbose:$false | Group-Object -AsHashTable VpcId) ?? @{}
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
    $_output = $_trt_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}