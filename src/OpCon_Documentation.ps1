param(
    $path,
    $sqlServer,
    $sqlDB,
    $sqluser,
    $sqlpassword
)

$ConnectionString = "server='$sqlServer';database='$sqlDB';user id='$sqluser';password='$sqlpassword'"
$Connection = New-Object System.Data.SQLClient.SQLConnection($ConnectionString)
$Connection.Open()
$sql =   "declare @doctable table (skdid int,jobname varchar(128),doctext varchar(max))  --table to store the final documentation
declare @temptable table (row int,skdid int, jobname varchar(128))             --temp table to reduce overhead
declare @counter int,@doccount int, @doccount2 int,@skdid varchar(10),@jobname varchar(128),@combinetext varchar(max)

insert into @temptable(row,skdid,jobname)
(SELECT ROW_NUMBER() OVER(ORDER BY skdid ASC) as row,skdid,jobname from (select distinct skdid,jobname FROM dbo.jdocs) as docs);

--Loops through the different distinct schedule/jobnames that have documentation
set @counter = (Select count(*) from @temptable)
while @counter > 0
begin
	set @skdid = (Select skdid from @temptable where [row] = @counter)
	set @jobname =  (Select jobname from @temptable where [row] = @counter)
	set @doccount = (select count(doctext) from dbo.jdocs where skdid=@skdid and jobname=@jobname)
	set @doccount2 = 1
	set @combinetext = ''

	--Loops through the documentation lines for each job and combines them
	while @doccount2 <= @doccount
	begin
		set @combinetext = @combinetext + (select doctext from (select row_number() over (order by skdid desc) as row,doctext from dbo.jdocs where skdid=@skdid and jobname=@jobname) as docs where row=@doccount2)
		set @doccount2 = @doccount2+1
	end

	--Adds the new combined documentation entry to our final table
	insert into @doctable
	values(cast(@skdid as int),@jobname,@combinetext)

	set @counter = @counter-1
end

select 
	UPPER(name.skdname) as Schedule
	,UPPER(jobs.jobname) as Job
	,CASE WHEN a.Documentation IS NULL THEN '' ELSE A.DOCUMENTATION END as [Documentation]
from dbo.jmaster as jobs
join dbo.sname as name
on name.skdid = jobs.skdid
LEFT OUTER JOIN
(select UPPER(name.skdname) as Schedule,UPPER(jobname) as Job,Doctext as [Documentation]
from @doctable as docs
join dbo.sname as name
on name.skdid = docs.skdid) AS A
ON a.job = jobs.jobname
order by schedule,job,documentation"

$Command = New-Object System.Data.SQLClient.SQLCommand($sql,$Connection)
$reader = $command.ExecuteReader()

$schedules = @()
$jobs = @()
While ($reader.Read())
{
    #Gets job documentation
    $schedules += $reader.GetValue(0)
    $jobs += @{"Schedule" = $reader.GetValue(0); "Job" = $reader.GetValue(1); "Documentation" = $reader.GetValue(2) }
}

$Connection.Close()
$Connection.Dispose()
#------------------------------------------------------
$ConnectionString = "server='$sqlServer';database='$sqlDB';user id='$sqluser';password='$sqlpassword'"
$Connection = New-Object System.Data.SQLClient.SQLConnection($ConnectionString)
$Connection.Open()
$sql = "select UPPER(name.skdname) as Schedule,CASE WHEN a.Documentation IS NULL THEN '' ELSE A.DOCUMENTATION END AS [Documentation]
from dbo.sname as name
left outer join
(select UPPER(name.skdname) as Schedule,sdocs.savalue as [Documentation]
from dbo.sname as name 
left outer join dbo.sname_aux as sdocs
on sdocs.skdid = name.skdid
where sdocs.safc=0) AS A
on a.schedule = name.skdname
order by schedule"
$Command = New-Object System.Data.SQLClient.SQLCommand($sql,$Connection)
$reader = $command.ExecuteReader()

$sdocs = @()
While ($reader.Read())
{
    #Gets information for the schedule
    $sdocs += @{"Schedule" = $reader.GetValue(0);"Documentation" = $reader.GetValue(1) }
}

$Connection.Close()
$Connection.Dispose()
#-------------------------------------------------------
$schedulesArray = @($schedules | Select-Object -Unique) | Sort-Object

$body = '
<html><head>
<style>
.content {
  padding: 0 18px;
  display: none;
  overflow: hidden;
  background-color: #f1f1f1;
}

.collapsible:after {
  content: "\02795"; /* Unicode character for "plus" sign (+) */
  font-size: 13px;
  color: white;
  float: right;
  margin-left: 5px;
}

.collapsible {
  background-color: #eee;
  color: #444;
  cursor: pointer;
  padding: 18px;
  width: 100%;
  border: none;
  text-align: left;
  outline: none;
  font-size: 15px;
}

.active:after {
  content: "\2796"; /* Unicode character for "minus" sign (-) */
}

.active, .collapsible:hover {
  background-color: #ccc;
}
</style></head>
<body>

'

For($x=0;$x -lt $schedulesArray.Count;$x++)
{
    $scheduleDocs = $sdocs | Where-Object{ $_.Schedule -eq $schedulesArray[$x] }
    $body = $body + "<button class='collapsible'><b>" + $schedulesArray[$x] + "</b> : " + $scheduleDocs.Documentation + "</button><div class='content'>"
    $jobs | ForEach-Object{ 
                                if($_.Documentation -ne "" -and $_.Documentation -like "*http*" -and $_.Documentation -notlike "*<a href=http*")
                                { 
                                    $linkStart = $_.Documentation.IndexOf("http")
                                    
                                    if($_.Documentation.Substring($_.Documentation.IndexOf("http")).IndexOf(" ") -gt 0)
                                    { $link = $_.Documentation.Substring($linkStart,($_.Documentation.Substring($linkStart).IndexOf(" ")+$linkStart)-$linkStart) }
                                    else
                                    { $link = $_.Documentation.Substring($linkStart) } 
                                    
                                    $newLink = "<a href="+$link+ " target='_blank'>"+$link+"</a>"
                                    $_.Documentation = $_.Documentation.Replace($link,$newLink)    
                                }          
                                
                                if($_.Schedule -eq $schedulesArray[$x])
                                {
                                    $body = $body + "<p>&emsp;<u>" + $_.Job.ToUpper() + "</u> : " + $_.Documentation + "</p>"
                                }
                          }
    $body = $body + "</div><br><br>" 
}

$body = $body + '

<script>
var coll = document.getElementsByClassName("collapsible");
var i;

for (i = 0; i < coll.length; i++) {
  coll[i].addEventListener("click", function() {
    this.classList.toggle("active");
    var content = this.nextElementSibling;
    if (content.style.display === "block") {
      content.style.display = "none";
    } else {
      content.style.display = "block";
    }
  });
} 
</script>

</body></html>'

$body | Out-File $path
