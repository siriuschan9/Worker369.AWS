using namespace System.Management.Automation

function Show-OrgTree
{
    [CmdletBinding()]
    [Alias('org_tree')]
    param ()

    $_root = Get-ORGRoot -Verbose:$false

    if ($_root)
    {
        $_root_node = [RootNode]::new($_root)
        $_root_node.Walk()
    }
}

class RootNode
{
    [System.Collections.Generic.List[OuNode]] $OuList
    [Amazon.Organizations.Model.Root]         $Root

    RootNode([Amazon.Organizations.Model.Root]$Root)
    {
        $this.Root   = $Root
        $this.OuList = [System.Collections.Generic.List[OuNode]]::new()
    }

    Walk()
    {
        $_dim   = [PSStyle]::Instance.Dim
        $_reset = [PSStyle]::Instance.Reset
        $_dashes = '-' * 80

        $_root_id = $this.Root.Id

        $_left = "▷ Root $_dim"
        $_right = " $_root_id $_reset"
        $_dashes = $_dashes.Remove(0, $_left.Length).Insert(0, $_left)
        $_dashes = $_dashes + $_right

        Write-Host $_dashes

        Write-Message -Progress "Traversing Organization Tree" "Retrieving OU for Root."
        Get-ORGOrganizationalUnitList -Verbose:$false $_root_id | Sort-Object Name |ForEach-Object {
            $_ou_node = [OuNode]::new($_)
            $_ou_node.Walk('  ')
        }
        Write-Message -Progress "Traversing Organization Tree" "Completed." -Complete
    }
}

class OuNode
{
    [Amazon.Organizations.Model.OrganizationalUnit] $OU

    OuNode([Amazon.Organizations.Model.OrganizationalUnit]$OU)
    {
        $this.OU = $OU
    }

    Walk([string]$Indent)
    {
        $_indent = $Indent

        $_dim   = [PSStyle]::Instance.Dim
        $_reset = [PSStyle]::Instance.Reset
        $_dashes = '-' * 80

        $_ou_id   = $this.OU.Id
        $_ou_name = $this.OU.Name

        $_left = "$_indent▷ $_ou_name $_dim"
        $_right = " $_ou_id $_reset"

        $_dashes = $_dashes.Remove(0, $_left.Length).Insert(0, $_left)
        $_dashes = $_dashes + $_right

        Write-Host $_dashes

        Write-Message -Progress "Traversing Organization Tree" "Retrieving OU for $_ou_name."
        Get-ORGOrganizationalUnitList -Verbose:$false $_ou_id | Sort-Object Name| ForEach-Object {
            $_ou_node = [OuNode]::new($_)
            $_ou_node.Walk($_indent + '  ')
        }

        Get-ORGAccountForParent -Verbose:$false $_ou_id | Sort-object Name | ForEach-Object {
            $_account_id    = $_.Id.Insert(4, '-').Insert(9, '-')
            $_account_name  = $_.Name

            $_display = '-' * 80
            $_left    = "$($_indent + '  ') ◆ $_account_name $_dim"
            $_right   = "   $_account_id $_reset"

            $_display = $_display.Remove(0, $_left.Length).Insert(0, $_left)
            $_display = $_display + $_right

            Write-Host $_display
        }
    }
}

class AccountNode
{
    [Amazon.Organizations.Model.Account] $Account

    AccountNode([Amazon.Organizations.Model.Account] $Account)
    {
        $this.Account = $Account
    }
}