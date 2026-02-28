<#
.SYNOPSIS
This cmdlet creates a new Internet Gateway.

.PARAMETER Name
The -Name Parameter specifies the Name of the Internet Gateway. See example 1.
If the -Tag parameter includes a 'Name' Tag, it will be overwritten by the -Name Paramater.

.PARAMETER Tag
The -Tag Parameter specifies the Tags to add to the Internet Gateway. See example 2.

.EXAMPLE
New-Igw igw-example-1

This example creates a new Internet Gateway and names it "igw-example-1".

.EXAMPLE
New-Igw -Tag @{Key = 'Environment'; Value = 'Production'},@{Key = 'CreatedOn'; Value = (Get-Date)} 'igw-example-2'

This example creates a new Internet Gateway and names it "igw-example-2".
It also adds "Environment" and "CreatedOn" Tags to it.
#>
function New-InternetGateway
{
    [Alias('igw_add')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Position = 0)]
        [string]
        $Name,

        [Parameter()]
        [Amazon.EC2.Model.Tag[]]
        $Tag
    )

    BEGIN
    {
        # Check if the default AWS Region is set in the caller's shell.
        if (-not ($_region = Get-DefaultAWSRegion))
        {
            $_error = New-ErrorRecord `
                -ErrorMessage "Default AWS region not set. Use Set-DefaultAWSRegion to set the default AWS region." `
                -ErrorId 'DefaultAWSRegionNotSet' `
                -ErrorCategory NotSpecified

            $PSCmdlet.ThrowTerminatingError($_error)
        }
    }

    PROCESS
    {
        # Use snake_case.
        $_name = $Name
        $_tag  = $Tag

        # Prepare TagSpecification parameter.
        $_make_tags_with_name    = { New-TagSpecification -ResourceType internet-gateway -Tag $_tag -Name $_name}
        $_make_tags_without_name = { New-TagSpecification -ResourceType internet-gateway -Tag $_tag }
        $_has_name               = $PSBoundParameters.ContainsKey('Name')
        $_tag_specification      = $_has_name ? (& $_make_tags_with_name) : (& $_make_tags_without_name)

        # Display What-If/Confirm prompt.
        if($PSCmdlet.ShouldProcess("Region: $($_region)", "Create New Internet Gateway"))
        {
            # Create the internet gateway.
            try {
                $_igw = New-EC2InternetGateway -Verbose:$false -TagSpecification $_tag_specification
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }

            # Output internet gateway ID.
            Write-Message -Output -Message "|- InternetGatewayId: $($_igw.InternetGatewayId)"
        }
    }
}