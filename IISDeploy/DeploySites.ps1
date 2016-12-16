Param(
    [ValidateSet("Pre", "Prod", "Test", "Local", ignorecase=$true)]
    [Parameter(Mandatory=$true)]
    [string]$EnvironmentType = "",

    #此项参数用于测试环境，因为测试环境会有多套。
    [int]$EnvironmentId = "0",

    [string]$AssemblySourcePath = "",

    [string]$AssemblyDestinationPath = ""
)
#创建应用程序池
function Create-AppPool(
    [Parameter(Mandatory=$true)]
    [string] $appPoolName
){
    $existsAppPool = Test-Path "IIS:\AppPools\$appPoolName"
    if($existsAppPool -eq $false)
    {
　　    $appPool =New-WebAppPool  $appPoolName
　　    #设置标识：LocalService=1;LocalSystem=2;NewworkService=3;ApplicationPoolIdentity=4
　　    $appPool.ProcessModel.IdentityType=4
　　    #设置.NET Framework 版本
　　    $appPool.managedRuntimeVersion="v4.0"
　　    #设置托管管道模式：集成=0；经典=1
　　    $appPool.ManagedPipelineMode=0
　　    $appPool.startMode="AlwaysRunning"
　　    #设置启用32位应用程序 false=0;true=1
　　    $appPool.enable32BitAppOnWin64=0
　　    $appPool | Set-Item
    }else{
        Write-Host "应用程序池【$appPoolName】已经存在" -ForegroundColor Yellow
    }
}

#创建站点
function Create-AppSite(
    #站点名
    [Parameter(Mandatory=$true)]
    [string] $siteName,
    #应用程序池
    [string] $appPool,
    #站点物理路径
    [string]$sitePath,
    #域名 可以是单个对象 可以是 对象集合 （对象Domain 包括 域名 HostName 和 端口 Port 端口 默认80）
    $appDomain

){
     $existsAppSite = Test-Path "IIS:\Sites\$siteName"
     if($existsAppSite -eq $false)
     {
        #新建站点
        Create-AppPool -appPoolName $appPool
        Write-Host "开始创建站点【$siteName】" -ForegroundColor Green
        New-Website $siteName -PhysicalPath $sitePath
        #删除默认绑定
        Remove-WebBinding -Name $siteName
        #绑定域名
        if($appDomain -is [Array])
        {
            $appDomain |ForEach-Object{
                New-WebBinding -Name $siteName -IPAddress "*" -HostHeader $_.HostName -Port $_.Port -Protocol http
            }
        }else{
            New-WebBinding -Name $siteName -IPAddress "*" -HostHeader $appDomain.HostName -Port $appDomain.Port -Protocol http
        }
        #设置应用程序池
        #如果没有传入应用程序池 则 默认程序池和站点名一样
        if($appPool -eq $null -or $appPool -eq "")
        {
            $appPool=$siteName.Clone()
        }
        # 设置身份验证等
     }else{
        Write-Host "站点【$siteName】已经存在" -ForegroundColor Yellow
    }
}

function CopySiteFiles
(
    #原路径 
    [string]$sourcePath,
    #目标路径
    [string]$targetPath
)
{
    Write-Output "正在拷贝文件..."
    Robocopy.exe -MIR $sourcePath $targetPath > $null
    Write-Output "文件拷贝完毕..."
}

$EnvironmentConfigs = @{
    Local = @{Postfix = "local.uoko.com"; AssemblySourcePath = "c:\code\star"; AssemblyDestinationPath = "c:\code\star"};
    Test =  @{Postfix = "test.uoko.com"; AssemblySourcePath = "\\fileserver.uoko.com\drops$\binary\test"; AssemblyDestinationPath = "d:\Site";};
    Pre =  @{Postfix = "pre.uoko.com"; AssemblySourcePath = "\\fileserver.uoko.com\drops$\binary\pre";AssemblyDestinationPath = "d:\Site";};
    Prod =  @{Postfix = "uoko.com"; AssemblySourcePath = "\\fileserver.uoko.com\drops$\binary\prod";AssemblyDestinationPath = "d:\Site"};
}
$SiteConfigs = @(
    @{DnsName = @("www","beijing","chengdu","wuhan","hangzhou"); BinaryPath = "UOKO.UShop.Site"; AppPool = $null;Port=80};
    @{DnsName = "m"; BinaryPath = "UOKO.UShop.WebApp"; AppPool = $null;Port=80};
    @{DnsName = "passport"; BinaryPath = "UOKO.UCenter.Passport"; AppPool =$null;Port=80};
    @{DnsName = "service"; BinaryPath = "UOKO.ServicePlatform.WebUI"; AppPool = $null;Port=80};
    @{DnsName = "backstage"; BinaryPath = "Maybach.WebSite"; AppPool = $null;Port=80};
    @{DnsName = "api.notify"; BinaryPath = ""; AppPool = $null;Port=80};
    @{DnsName = "eval"; BinaryPath = "UOKO.Evaluation.Site"; AppPool = $null;Port=80};
    @{DnsName = "cashier"; BinaryPath = ""; AppPool = $null;Port=80};
    @{DnsName = "api.trade"; BinaryPath = ""; AppPool = $null;Port=80};
)

$global:EnvironmentConfig = $EnvironmentConfigs.$EnvironmentType

if(![string]::IsNullOrEmpty($AssemblySourcePath))
{
    $EnvironmentConfig.AssemblySourcePath = $AssemblySourcePath;
}

if(![string]::IsNullOrEmpty($AssemblyDestinationPath))
{
    $EnvironmentConfig.AssemblyDestinationPath = $AssemblyDestinationPath;
}

if(![string]::IsNullOrEmpty($DbSourcePath))
{
    $EnvironmentConfig.DbSourcePath = $DbSourcePath;
}

if(![string]::IsNullOrEmpty($DbDestinationPath))
{
    $EnvironmentConfig.DbDestinationPath = $DbDestinationPath;
}

Write-Host "开始部署..." -ForegroundColor Green

CopySiteFiles -sourcePath $EnvironmentConfig.AssemblySourcePath -targetPath  $EnvironmentConfig.AssemblyDestinationPath

foreach($site in $SiteConfigs){
     
     if($site.DnsName -is [Array])
     {
        $defaultDnsName=$site.DnsName[0]
        $defaultDomain= [string]::Concat($defaultDnsName,".", $EnvironmentConfig.Postfix)


        $appDomain=@()
        $site.DnsName|ForEach-Object {
            $appDomain+=(,@{HostName=[string]::Concat($_,".", $EnvironmentConfig.Postfix);Port=$site.Port})
        }
        if($EnvironmentConfig.$EnvironmentType -eq "Test" -and $EnvironmentConfig.$EnvironmentId -gt 0)
        {
            #测试多环境域名
            $defaultDomain= [string]::Concat($defaultDnsName, ".", $EnvironmentId, ".", $EnvironmentConfig.Postfix)
            $appDomain=@()
            $site.DnsName|ForEach-Object {
                $appDomain+=(,@{HostName=[string]::Concat($_, ".", $EnvironmentId,".", $EnvironmentConfig.Postfix);Port=$site.Port})
            }
        }
     }else
     {
        $defaultDnsName=$site.DnsName
        $defaultDomain= [string]::Concat($defaultDnsName,".", $EnvironmentConfig.Postfix)
        if($EnvironmentConfig.$EnvironmentType -eq "Test" -and $EnvironmentConfig.$EnvironmentId -gt 0)
        {
            #测试多环境域名
            $defaultDomain= [string]::Concat($defaultDnsName, ".", $EnvironmentId, ".", $EnvironmentConfig.Postfix)
        }
         $appDomain= @{HostName=$defaultDomain;Port=$site.Port}
     }

     #本地安装一般直接将网站连接到代码目录
    if($EnvironmentType -eq "Local")
    {
        $destinationPath = Join-Path -Path $EnvironmentConfig.AssemblyDestinationPath $site.BinaryPath
    }
    else
    {
        $destinationPath = Join-Path -Path $EnvironmentConfig.AssemblyDestinationPath $defaultDomain
    }
    #创建站点
    Create-AppSite -siteName  $defaultDomain -appPool  $defaultDomain -sitePath $destinationPath -appDomain $appDomain
}
Write-Host "完成部署..." -ForegroundColor Green
