<?php

if(file_exists("test.php")) include_once("test.php");
include_once("autoload.php");
include_once("htmLawed.php");
include_once("html_classes.php");

/*
################################################################################

		Univerzální funkce - jejich jména jsou malými písmeny
		
		27.12.2010 - Změna funkce "sqlpagerun", zcela jiná struktura prvního resultu,
					 aby bylo dosaženo nezávislosti na PHP - eval
		04.08.2011 - Přidána funkce "custom_module", která zjišťuje přítomnost modulu
		21.09.2011 - Vylepšení funkce "fetch_datarow"
		19.10.2011 - funkce csv_export má nový parametr na vnucení jiných záhlaví
		02.05.2012 - funkce intliteral - přidán parametr pro počet desetinných míst
		12.06.2012 - Explicitní stanovení typu BUTTON pro jiné prohlížeče
		19.11.2012 - Umožnění zadávat číselné hodnoty s mezerami (oddělovač tisíců)
		10.09.2013 - Funkce pro podporu JSONa: JSON_ENCODE_CP, JSON_DECODE_CP, ICONV_ARRAY
		21.02.2014 - Zařazení jQuery a využití pro textarea.autosize
		24.02.2014 - Vylepšení funkce CHECK_ACCESS
		06.12.2015 - Funkce stripAphostrophes
		03.01.2016 - Propojení stejnoměnné a globální proměnné ve funkci "sessionreg"
		28.01.2016 - Přidání funkcí ramsesEncrypt a ramsesDecrypt
		14.03.2016 - Odstranění funkce "ereg" z dateliteral
		17.08.2016 - Podpora PDO driverů
		02.12.2016 - Memory leak v "csv_export()"
		04.01.2017 - Do výpisu při chybě přidán backtrace
################################################################################
*/

// Funkce numberFormat nastavuje default ceske separatory, nastavuje uvodni nulu
// a neciselne hodnoty vraci beze změny

function numberFormat($n,$dec=0,$sep='.',$th=' '){
  if(is_numeric($n)){
    $r=number_format($n,$dec,$sep,$th);
    return ($r[0]==$sep)?$r="0$r":$r;
  }
  return (string)$n??'';
}

function fform($url,$body,$params=''){return "<form name=f id=f action=\"$url\" method=post enctype=\"multipart/form-data\" $params>$body</form>";}

// attrliteral vytvoří z předané hodnoty textový literál v uvozovkách, vhodný pro použití jako atribut pro script HTML
function htmlliteral($xml){return '"'.htmlspecialchars($xml ?? '').'"';}

// xmlliteral vytvoří z předané hodnoty textový literál v uvozovkách, vhodný pro použití jako atribut v XML
// zatím se používá pouze ve FusionCharts, který vyžaduje navíc replacnout procento sekvencí '%25'

function xmlliteral($xml){return jsliteral(htmlspecialchars(str_replace('&','%26',str_replace('%','%25',$xml ?? ''))));}

// jsliteral vytvoří z předané hodnoty textový literál pro použití v JavaScriptu, nahrazuje pouze nové řádky a dvojité uvozovky
function jsliteral($s){
	//return '"'.str_replace("\r","\\r",str_replace("\n","\\n",htmlspecialchars($s))).'"';
	//return '"'.str_replace("\r","\\r",str_replace("\n","\\n",addslashes($s))).'"';
	if($s===null) return '""';
	$s = str_replace("\\","\\\\",$s);
	return '"'.str_replace("\r","\\r",str_replace("\n","\\n",str_replace('"','\"',($s)))).'"';
}


// regfile: vrátí jméno dočasného souboru, pokud byl úspěšně uploadnut

function regfile($fn,&$full_name=null){
	if(array_key_exists($fn,$_FILES)){
		$F=&$_FILES[$fn];
		if(is_uploaded_file($tmpname=$_FILES[$fn]['tmp_name']) && is_readable($tmpname) && $_FILES[$fn]['size']){
			$full_name=array_item($F,'full_path','');
			return $tmpname;
		}
	}
	return '';
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
// SQLRUN: funguje stejně jako mssql_query, navíc ošetřuje chyby a zapisuje historii příkazů kvůli ladění //
////////////////////////////////////////////////////////////////////////////////////////////////////////////

function sqlrun($cmd) { 
 
GLOBAL $sqlcmdlist,$dbms,$dbconnection,$debugmode,$dbquery,$sqlrun_debugonly,$result_wwwsession,
	$logSqlCmdList,$sqlRows,$lastSql; 

$cmd=str_replace('@o@',intliteral(array_item($result_wwwsession,'organization','0')),$cmd);
$cmd=str_replace('@p@',intliteral(array_item($result_wwwsession,'crp_profile','0')),$cmd);
$lastSQL=$cmd=str_replace('@r@',intliteral(array_item($result_wwwsession,'crr_review','0')),$cmd);

if($sqlrun_debugonly){debugitem('sqlrun',$cmd); return true;}

if($debugmode and $logSqlCmdList) $sqlcmdlist .= "\r\n$cmd";

if ($dbms == 'sqlsrv') {
    if (is_resource($dbquery) or is_object($dbquery)) {
        sqlsrv_free_stmt($dbquery);
    }
    $options = ['ReturnDatesAsStrings' => true];
    $dbquery = sqlsrv_query($dbconnection, $cmd, [], $options);
    if ($dbquery !== false) {
        return $dbquery;
    }
    if ($e = sqlsrv_errors(SQLSRV_ERR_ERRORS)) {
        $m = '';
        foreach ($e as $ei){
        	//if(substr($ei['SQLSTATE'],0,2)=='01') continue;
					$m .= var_export($ei,true) . "\n";
				}
		if(!$m) return false;
		$msg = "\r\nError at SQL command:\r\n$cmd\r\n\r\nSQL command history:\r\n$sqlcmdlist\r\n\r\n$m";
		fatal_error("Ramses SQL Error",$msg,strpos($m,"deadlock"));
    }
} elseif($dbms=='pdo') {
	if(is_object($dbquery)) $dbquery->closeCursor();
	if ($dbquery = $dbconnection->query("/**/$cmd")){
		$sqlRows=$dbquery->rowCount();
		return $dbquery;
	}
	if (($m = $dbconnection->errorInfo()) && ($m=$m[2])) {
		$sqlcmdlist .= "\r\nMessage: $m\r\n$cmd";
		if($debugmode) $sqlcmdlist .= "\r\nMessage: $m\r\n";
		if (substr_count($m, "Changed database context") > 0
		|| substr_count($m, "Warning:") > 0) return 1;
		else {fatal_error("SQL Error","$sqlcmdlist\r\n\r\nMessage: $m"); return false; }
	};
} elseif($dbms!='odbc') {
	if(is_resource($dbquery) or is_object($dbquery)) mssql_free_result($dbquery);
	if ($dbquery = @mssql_query($cmd)){
		$sqlRows=mssql_num_rows($dbquery);
		return $dbquery;
	}
	if ($m = mssql_get_last_message()) {
		if($debugmode) $sqlcmdlist .= "\r\nMessage: $m\r\n";
		if (substr_count($m, "Changed database context") > 0
		|| substr_count($m, "Warning:") > 0) return 1;
		else {fatal_error("SQL Error",nl2br("$sqlcmdlist\r\n\r\n$cmd\r\n$m")); return false; }
	};
} else { // Tato část je řešení pro ODBC
	cleanup_result();
	if ($dbquery = @odbc_do($dbconnection,$cmd)){
		$sqlRows=odbc_num_rows($dbquery);
		return $dbquery;
	};

	if ($m = odbc_errormsg()) {
		if(($smeti=strpos($m,"\x00"))!==false) $m=substr($m,0,$smeti);
		//debugitem("smeti",$smeti);
		//debugitem("sqlrun error: $cmd",bin2hex(odbc_errormsg()));
		$msg = "\r\nSQL command history:\r\n$sqlcmdlist\r\n\r\nError at SQL command:\r\n$cmd\r\n\r\n$m";
		if (substr_count($m, "Changed database context") > 0
		|| substr_count($m, "Warning:") > 0) return 1;
		else {
			fatal_error("Ramses SQL Error",$msg,strpos($m,"deadlock"));
		}
	}; 
	return 1;
	};
};
//
// NEXT_RESULT: Odstíní platformově toto volání
// 08.09.2009: POZOR !!! pro ODBC není třeba explicitně tuto funkci volat, pokud předešlý result-set byl načten do konce
//		Proto byl přidán parametr $force, který vynutí volání i v případě ODBC k zahození zbytku result-setu
//		Pak jsem zjistil, že je to blbost, ale v jednom místě mi přeskočí jeden result-set, ošetřil jsem to extra na stránce page_info2_rpt_crosstab
function next_result($res=null,$force=true){
	global $dbms,$dbconnection,$dbquery;
	static $count=0;
	$count++;
	static $notSupportedPDO=array("sqlite","pgsql");
	if(!$res) $res=$dbquery;
	if($res===false) return false;
	if (@$dbms=="sqlsrv") return sqlsrv_next_result($res);
	if (@$dbms=="odbc") return $force?odbc_next_result($res):true;
	if (@$dbms=='pdo'){
		if(in_array($dbconnection->getAttribute(PDO::ATTR_DRIVER_NAME),$notSupportedPDO)) return false;
		$nrstatus='XX';
		//print "<div>Calling next rowset force=$force, count=$count</div>";
		//if($count==5) return;
		$r=$force?($nrstatus=$res->nextRowset()):true;
		//print "<div>nrstatus=$nrstatus $count</div>";
		return ;
	}
	return @mssql_next_result($res);
}

// DATA_SEEK: Odstíní platformově toto volání
function data_seek($res, $num){
	global $dbms;
	if (@$dbms=="odbc") return odbc_data_seek($res, $num);	
	return mssql_data_seek($res, $num);
}

// FREE_RESULT: Odstíní platformově toto volání
function free_result($res=null){
	global $dbms,$dbquery;
	if(!$res) $res=$dbquery;
	//debugitem("FREE RESULT",$res);
	if (@$dbms=="sqlsrv") return @sqlsrv_cancel($res);
	if (@$dbms=="sybase") return sybase_free_result($res);
	if (@$dbms=="pdo") return $res->closeCursor();
	if (@$dbms=="odbc") {
		while((is_resource($res) or ($res instanceof ODBCResult)) and @odbc_next_result($res)) odbc_free_result($res);
		return;
	};
	return mssql_free_result($res);
}

// NUM_ROWS: Odstíní platformově toto volání
function num_rows($res){
	global $dbms,$dbconnection;
	if ($dbms=="odbc") return odbc_num_rows($res);
	if ($dbms=="sybase") return sybase_num_rows($res);
	if ($dbms=="sqlsrv") return sqlsrv_rows_affected($res);
	if ($dbms=="pdo") return $res->rowCount();
	return mssql_num_rows($res);
}

function db_field_type($colname) {
    global $dbms, $dbquery;

    if ($dbms === 'sqlsrv') {
        $fields = sqlsrv_field_metadata($dbquery);
        if ($fields !== false) {
            $names = array_column($fields, 'Name');
            $index = array_search($colname, $names);
            if ($index !== false) {
                $typeNum = $fields[$index]['Type'];
                return sqlsrv_type_to_string($typeNum);
            }
        }
    } elseif ($dbms === 'odbc') {
        $colnum = odbc_field_num($dbquery, $colname);
        if ($colnum !== false) {
            return strtolower(odbc_field_type($dbquery, $colnum));
        }
    }
    return null;
}

function sqlsrv_type_to_string($type) {
    static $map = [
        // === PŮVODNÍ KLÍČE (Legacy / System ID) ===
        // Tyto tam necháme, aby se nic nerozbilo, pokud by přišly ze starší části kódu
        56 => 'int',
        127 => 'bigint',
        62 => 'float',
        59 => 'real',
        108 => 'numeric',
        106 => 'decimal',
        175 => 'char',
        167 => 'varchar',
        231 => 'nvarchar',
        239 => 'nchar',
        61 => 'datetime',
        58 => 'smalldatetime',
        40 => 'date',
        41 => 'time',
        104 => 'bit',
        128 => 'binary',
        129 => 'varbinary',
        130 => 'image',

        // === NOVÉ KLÍČE (Nutné pro PHP 8.x + sqlsrv driver) ===
        // Hodnoty, které reálně vrací sqlsrv_field_metadata()
        
        // 1. Binární data (to je váš aktuální problém s -4)
        -4  => 'image',      // SQL_LONGVARBINARY -> reprezentuje Image / Varbinary(max)
        -3  => 'varbinary',  // SQL_VARBINARY
        -2  => 'binary',     // SQL_BINARY
        
        // 2. Textová data
        -1  => 'text',       // SQL_LONGVARCHAR -> reprezentuje Text / Varchar(max)
        1   => 'char',       // SQL_CHAR
        12  => 'varchar',    // SQL_VARCHAR
        -8  => 'nchar',      // SQL_WCHAR
        -9  => 'nvarchar',   // SQL_WVARCHAR
        -10 => 'ntext',      // SQL_WLONGVARCHAR
        
        // 3. Čísla
        4   => 'int',        // SQL_INTEGER
        5   => 'smallint',   // SQL_SMALLINT
        -6  => 'tinyint',    // SQL_TINYINT
        -5  => 'bigint',     // SQL_BIGINT
        6   => 'float',      // SQL_FLOAT
        7   => 'real',       // SQL_REAL
        2   => 'numeric',    // SQL_NUMERIC
        3   => 'decimal',    // SQL_DECIMAL
        -7  => 'bit',        // SQL_BIT
        
        // 4. Datum a čas
        91  => 'date',       // SQL_TYPE_DATE
        93  => 'datetime',   // SQL_TYPE_TIMESTAMP
        -154 => 'time',      // SQL_SS_TIME2
        -155 => 'datetimeoffset',
    ];

    return $map[$type] ?? "unknown type: $type";
}
//
// SQLPAGERUN: Zavolá proceduru s parametry a převezme první result set, ve kterém je seznam přeložených frází
// 27.12.2010 - změněná struktura prvního result-setu

function sqlpagerun($cmd,$printtitle=1){
	global $T_PAGE_TITLE, $sqlprocresult, $dbms, $xmloutput, $private_file, $ajaxpage, $dbquery, $menu_title,
		$PAGE_ACCESS_DENIED, $T_PAGE_ACCESS_DENIED, $pageitem_array, $pagetable_array, $cbxCenter, $myOrgShortname;
	//print "pagerun start";
	$PAGE_ACCESS_DENIED=false;
	$cbxCenter=true;
	
	// Zavolám proceduru a první result-set zpracuju
	
	getCloseWindowImg();
	if($r=$dbquery=sqlrun($cmd)){
		$anyItem=0;
		while($a=fetch($r)){
			$anyItem=1;
			$ot=$a['objtype'];
			$vn=$a['varname'];
			if($a['charvalue']===null) $a['charvalue']='';
			$val=str_replace('{$myOrgShortname}',$myOrgShortname??'',$a['charvalue']??'');
			// 
			if($ot=='pageColumn'){
				$colname=$a['objname'];
				unset($pi);
				if(is_array($pageitem_array) && array_key_exists($colname,$pageitem_array))
					$pi=&$pageitem_array[$colname];
				else {
					$pi=new PageItem();
					$pageitem_array[$colname]=&$pi;
					$pi->name=$colname;
				}
				$pi->$vn=$val;
				$GLOBALS["pageitem_$colname"]=&$pi;
				//debugitem('A',$a);
				//debugitem('PI '.$colname,$pi);
				//debugitem('keys',array_keys($pageitem_array));
				unset($pi);
			} elseif($ot=='pageTable'){
				$colname=$a['objname'];
				if(is_array($pagetable_array) && array_key_exists($colname,$pagetable_array))
					$pi=&$pagetable_array[$colname];
				else {
					$pi=new PageTable();
					$pi->name=$colname;
					$pagetable_array[$colname]=&$pi;
				}
				$pi->$vn=$val;
				$GLOBALS["pagetable_$colname"]=&$pi;
				//debugitem('A',$a);
				//debugitem('PI',$pi);
				//debugitem('keys',array_keys($pageitem_array));
				unset($pi);
			}
			
			if($ot=='global'){$GLOBALS[$vn]=$val;}
			
			if($ot=='action' && $vn=='timeoutAlert' && $val) sendAlert(1200000);
		};
		if($anyItem==0){
			print "<script>document.location='page_enter_licence.php?redirectFrom=pagePhrases';</script>";
			die();
		}
		//debugg('pageitem_status');
		//debugg('T_PAGE_ACCESS_DENIED');
		if($menu_title) $T_PAGE_TITLE=$menu_title; // Je-li předán název menu, pak má přednost jako název stránky
		if($PAGE_ACCESS_DENIED){
			print $T_PAGE_ACCESS_DENIED;
			die();
		}
		if(!$xmloutput and !$private_file and $printtitle and !$ajaxpage){
			if(is_string($printtitle) && $printtitle) set_pagetitle($printtitle);
			else
				print_to_ElementById('pagetitle',htmlspecialchars($T_PAGE_TITLE));
		};
	};
	next_result($r);
	return $r;
};

function sqlpagerun_old($cmd,$printtitle=1){
	global $T_PAGE_TITLE, $sqlprocresult, $dbms, $xmloutput, $private_file, $ajaxpage, $dbquery, $menu_title,
		$PAGE_ACCESS_DENIED, $T_PAGE_ACCESS_DENIED;
	//print "pagerun start";
	$PAGE_ACCESS_DENIED=false;
	if($r=$dbquery=sqlrun($cmd)){
		while($a=fetch($r)){
			//print "Eval (".strlen($a[0])."): $a[0]<BR />";
			
			//if(!strpos($a['php_command'],'note_target')){
			//debugitem('ANO eval '.$cmd,$a['php_command']);
				eval($a[0]);
				//print "$a[0]<br>";
			 //} else debugitem('NE eval '.$cmd,$a['php_command']);
		};
		if($menu_title) $T_PAGE_TITLE=$menu_title; // Je-li předán název menu, pak má přednost jako název stránky
		if($PAGE_ACCESS_DENIED){
			print $T_PAGE_ACCESS_DENIED;
			die();
		}
		if(!$xmloutput and !$private_file and $printtitle and !$ajaxpage){
			if($printtitle!==1) set_pagetitle($printtitle);
			else
				print_to_ElementById('pagetitle',htmlspecialchars($T_PAGE_TITLE));
		};
	};
	next_result($r);
	return $r;
};

// SQLPROCRESULT: Funkce s volání procedury, zabezpečující převzetí chybové zprávy

function sqlprocresult($cmd){
	global $sqlprocresult, $sqlnrows, $dbquery;
	if(sqlrun($cmd)){
		$sqlprocresult=fetch();
		//debugitem("sqlprocresult OK",$sqlprocresult);
		free_result();
		if(($i=array_item($sqlprocresult,0,0))<0) $sqlnrows=$sqlprocresult[0]; else @$sqlnrows += $i;
	} else {
		//debugitem("Chyba SQLRUN");
		return -1;
	}
	return 1;
};

function print_to_ElementById($id,$txt,$mousetip=''){
	global $no_html,$jsyntax;
	if($no_html) return;
	$mousetip=htmlspecialchars($mousetip);
	$pt=jsliteral($txt);
	if($mousetip){
		$mousetip=str_replace("\r","\\r",str_replace("\n","\\n",addslashes($mousetip)));
		$pt=jsliteral("<span title=\"$mousetip\">$txt</span>");
	}
	//print "<SCRIPT>if(e=document.getElementById('$id')) e.innerHTML=$pt;</SCRIPT>";
	$jsyntax .= "\r\nif(e=document.getElementById('$id')) e.innerHTML=$pt;";
}

function set_pagetitle($title,$alt=''){
	global $T_PAGE_TITLE, $jsyntax;
	$T_PAGE_TITLE=$title;
	print_to_ElementById('pagetitle',$title,$alt);
}

function print_sqlprocresult(){
	global $sqlprocresult,$sqlnrows,$T_SQLNROWS,$no_title,$sqlcmdlist;
	$msg='';
	if(is_array($sqlprocresult)){
		if($msg=@$sqlprocresult[1]){
			$s=($sqlprocresult[0]<0)?" style=\"color: red; font-weight: bold\"":" style=\"color: green; font-weight: bold\"";
			if($sqlprocresult[0]<0 and $no_title){
				print "<h3 style=color:red>$msg</h3>";
				return;
			}
			$msg="<span$s>$msg</span>";
			if(!$no_title) print_to_ElementById('sqlprocresult',$msg);
			return $msg;
		}
		else
		$sqlprocresult=str_replace("%1%",$sqlnrows,$T_SQLNROWS);
	}
	$msg="<span style=\"color: green; font-weight: bold;\">".htmlspec($sqlprocresult)."</span>";
	if($sqlprocresult and !$no_title) print_to_ElementById('sqlprocresult',$msg);
	return $msg;
};
/*
	FETCH: fetchne řádek do pole, přičemž odstraní MSSQL chybu, která vrací mezeru místo empty
	zároveň konvertuje datum z objektu DateTime na ODBC formát
*/

function fetch($q=null){
	global $dbms,$dbquery;
	if(!$q) $q=$dbquery;
	$r='';
	if($dbms=="mssql"){
		$r=mssql_fetch_array($q,MSSQL_BOTH);
		if($r) {
			foreach($r as $k => $v){
				//if($v == '0') continue;
				if($v === ' ') {$r[$k]='';};
			};
		}
	}
	if($dbms=="pdo"){
		$r=$q->fetch();
		//debugitem('datarow',$r);
		if($r) {
			foreach($r as $k => $v){
				//if($v == '0') continue;
				if($v === ' ') {$r[$k]='';};
			};
		}
	}
	elseif($dbms=="sqlsrv"){
		znovu:
		$r=sqlsrv_fetch_array($q,SQLSRV_FETCH_BOTH);
		// Prozkoumám chyby, jestli to nezpůsobil pouhý print
		if($r===false){
			$m=sqlsrv_errors();
			$m1=end($m);
			if(array_item($m1,'code',0)==-26) return array();
			if(in_array(array_item($m1,'code',0),array(-28,-22))){
				$r=next_result();
				goto znovu;
			}
			debugitem("ERROR",$m);
		}
		if($r) {
			foreach($r as $k => &$v){
				if(is_object($v)) {
					$v=$v->format('Y-m-d H:i:s');
					if(substr($v, -3)==':00') $v=substr($v,0,-3);
				}
				if($v === ' ') {$r[$k]='';};
			};
		}
	}
	else {
		//debugitem('fetch1',"$q");
		$o=@odbc_fetch_object($q);
		//debugitem('fetch2',$o);
		if(!is_object($o)) return false;
		$ret=@get_object_vars($o);
		$i=0;
		if($ret) foreach($ret as $v) $ret[$i++]=$v;
		return $ret;
	};
	return $r;
};

// FATAL_ERROR: oznámí chybu a skončí.
function fatal_error($usr='', $x="Unspecified error", $deadlock=0){
	global $debugmode,$result_wwwsession,$error_mailto,$SID,$ORIGINAL_REMOTE_ADDR,$dbserver,$use_dbname;
	$get=to_string($_GET);
	if(array_key_exists('pwd',$_POST)) $_POST['pwd']='*** Password is hidden from security reasons ***';
	$post=(isset($_POST))?"\r\nPOST=".to_string($_POST):"";
	$sess=(isset($_SESSION))?"\r\nSESSION=".to_string($_SESSION):"";
	$cn=getenv('COMPUTERNAME');
	$cookie=@$_SERVER['HTTP_COOKIE'];
	$time=date("d.m.Y H:i:s");
	//$dbname=array_item($result_wwwsession,'database_name');
	$host=gethostname();
	$bt=debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS);
	ob_start(); debug_print_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS); $bt=ob_get_clean(); ob_end_clean();
	//print nl2br($bt);
	@$msg="
Time=$time
Server=$_SERVER[SERVER_NAME] on \"$host\" $cn
DbServer=$dbserver
Database=$use_dbname
Login=$result_wwwsession[user_login]
Name=$result_wwwsession[organization_name]/$result_wwwsession[user_fullname]

BackTrace:
$bt

Error: $usr
Detail:
$x

Request properties:
URL=$_SERVER[REQUEST_URI]
REMOTE_ADDR=$_SERVER[REMOTE_ADDR]
ORIGINAL_REMOTE_ADDR=$ORIGINAL_REMOTE_ADDR
SESSIONID=$SID
COOKIES=$cookie
GET=$get$post$sess";
	$msg=str_replace('<br />',"\r\n",$msg);
	$msg=str_replace("\n","\r\n",$msg);
	$msg=str_replace("\r\r","\r",$msg);		
	//mail("hink@rac.cz","Unexpected error",$msg,'');
	write_log($msg);
	syslog(LOG_ERR,$msg);
	//$msg=str_replace("\r","RRRRRR",$msg); $msg=str_replace("\n","NNNNNN",$msg); $debugmode=1;debugitem('MSG',$msg);debugprint();
	if($debugmode){
		debugprint();
		$x = nl2br(htmlspecialchars($msg));
		print "<DIV align=\"left\"><H1>Unexpected error</H1>
		<H2>$usr</H2>
		<p style=color:magenta>This report is displayed thanks your debug setting.<br />If you are not a developer team member, send the information to the provider.</p>
		<p style=color:brown>$x</p>
		</DIV></body></HTML>";
	} else {
		if(!$error_mailto) $error_mailto='hink@rac.cz';
		$time=$t=time();
		$i=true;
		if($ORIGINAL_REMOTE_ADDR!=='212.24.158.131'){ // Nezasílat e-maily, pokud je to testovací request Nagiosu
			$i=mail($error_mailto,"Ramses error report",$msg,'')?"OK":"Error, message saved into log file";
		}
		if($deadlock)
			print "<DIV style=text-align:left><H1>System overload / systém je přetížen</H1>
			<DIV style=color:blue>Try to repeat action in a while / Zkuste akci za chvíli zopakovat</DIV></DIV></body></HTML>";
		else {
			$time=time();
			if($i AND (($time=time())>$t+10)){
				$i="Služba pro odeslání mailu neodpověděla včas. Zpráva nemusela být řádně odeslána.";
				$ien="The mail sending service did not respond in time. The message may not have been sent properly.";
			} else {
				$ien=$i?"OK":"ERROR";
				$i=$i?"OK":"Chyba";
			}
			print "
			<DIV align=\"left\">
			<H2>Na serveru nastal problém</H2>
			<div>Detaily o problému byly zapsány do deníku a budou zaslány vývojovému týmu k řešení.<div>Odeslání mailu .... $i</div>
			</div></DIV>

			<DIV align=\"left\">
			<H2>A problem ocurred</H2>
			<div>The details of the issue have been logged and will be sent to the development team for resolution.<div>Mail-status: $ien</div>
			</div></DIV>

			</body></HTML>";
		}
	}
	die();
};

function to_string($val){
	if(is_array($val) or is_object($val)){
		ob_start();
		print_r($val);
		$s=ob_get_contents();
		ob_clean();
		return $s;
	}
	else
		return $val;
}
// CHARLITERAL: Převede znaky na literál v apostrofech

function charliteral($c,$len=0){
	//debugitem('charliteral ',$c);
	if($c===null) return "NULL";
	if($len>0) $c=substr($c,0,$len);
	$c=str_replace("\r\n","\n",$c);
	$c=str_replace("\x00","\n",$c);
	return "'".str_replace("'","''",$c)."'";
};

// GUIDLITERAL: Převede UUID ve stringu na literál v apostrofech, pokud je syntaxe špatná, generuje NULL

function guidliteral($c){
	if(!$c) return 'NULL';
	if($c[0]=='{') $c=substr($c,1,-1);
	return is_guid($c)?"'$c'":'NULL';
};


// INTLITERAL: Převede znaky na literál v apostrofech

function intliteral($c,$prec=0){
	if(($c??'')==="") return 'NULL';
	if(substr($c,0,2)=='ID') $c=substr($c,2); // Kvůli CSV v Excelu je třeba předřadit ID pro bigint 
	$c=str_replace(' ','',$c);
	$c=str_replace(',','.',$c);
	if(!is_numeric($c)) return 'NULL';
	return bcadd($c,"0",$prec);
};

// INTLITERALLIST: Převede znaky na seznam čísel v apostrofech

function intliterallist($c){
	$c=$c??'';
	if($c!==''){
		$a=explode(',',$c);
		foreach($a as $i=>$cls){
			$cls=str_replace(' ','',$cls);
			$a[$i]=bcadd($cls,'0');
		}
		return "'".implode(',',$a)."'";
	}
	return "''";
}

// Vrati datum v ODBC formatu nebo false

function date_from_string($s){
	$s=$s??'';
	if(!$s || strtolower($s)=='null') return false;
	$formatList=array(
		"j.n.Y",
		"j.n.y",
		"j.n.y H:i",
		"j.n.Y H:i",
		"Y-m-d H:i:s",
		"Y-m-d H:i",
		"dmy",
		"dmy H:i",
		"Y-m-d",
		);
	//debugitem("date from string",$s);
	foreach($formatList as $format){
		$d=date_parse_from_format($format,$s);
		//debugitem($format,$d);
		if($d['error_count']) continue;
		if(($year=$d['year'])<30) $year += 2000;
		if($year<100) $year += 1900;
		$month=substr("00$d[month]",-2);
		$day=substr("00$d[day]",-2);
		$hour=substr("00$d[hour]",-2);
		$minute=substr("00$d[minute]",-2);
		$second=substr("00$d[second]",-2);
		return "$year-$month-$day $hour:$minute:$second";
	}
	return false;
}

// DATELITERAL: Převádí datum do formátu vhodného pro zápis do databáze

function dateliteral($input){
	//prevadi ceske datum pro zapis do databaze
	$input=trim($input??'');
	while(($temp=str_replace('  ',' ',$input))!=$input) $input=$temp;
	if (strpos($input, ".")):
		 $a=explode(".", $input);
		 if(count($a)<2) return 'NULL';
		 if(count($a)<3) $a[2]= $rok=date("Y");
		 list($den, $mesic, $rok)=$a; //predpokladame cesky datum ve formatu den.mesic.rok
	else:
		$a=explode("-", $input);
		if(count($a)<3) return 'NULL';
		if(count($a)<3) $a[2]= $rok=date("Y");
		list($rok, $mesic, $den)=$a; // nebo ODBC formátu yyyy-mm-dd
	endif;
	$den=(int)$den; $mesic=(int)$mesic; $rok=(int)$rok; //bereme jen ciselne hodnoty
	if ($rok<100) { $rok += 2000; if($rok>date("Y")+2) $rok -= 100;};
	if (!checkdate($mesic, $den, $rok)) return 'NULL';
	
	//if (@ereg("([0123456789]{1,2}:[0123456789]{2})", $input, $casti))
	$hodina=$minuta=0;
	$i=strrpos($input," ");
	if($i>0) $input=substr($input,$i); else $input="";
	if(count($casti=explode(':',$input))>1){
		$hodina=$casti[0];
		$minuta=$casti[1];
	}
	$hodina = (int)$hodina; 
	$minuta = (int)$minuta;
	$datum= sprintf("%04d-%02d-%02d", $rok,$mesic,$den);
	if (strlen($hodina)>0) $datum.=sprintf(" %02d:%02d",$hodina,$minuta);
	return "'$datum'";
};

// BinLiteral: Převádí a kontroluje binární string, povoleny jsou běžné blank-znaky

function varbinliteral($input){
	$output='0x';
	$input=trim(strtolower($input));
	if(substr($input,0,2)=='0x'){
		$blank=array(' ',"\n","\r","\t");
		for($i=2;$i<strlen($input);$i++){
			if(($c=(string)$input[$i])>='0' and $c<='9' or $c>='a' and $c<='f'){
				$output .= $c;
			}
			else{
				if(in_array($c,$blank)) continue;
				return 'NULL';
			}
		}
		return $output;
	} else {
		return 'NULL';
	}
}
// LOGGED slouží jen pro kontrolu, zda je uživatel nalogován (pokud ne, na ostatních stránkách nebude tato funkce
// známá - volá se s @ aby nehlásila chyby

function logged() {};

/*
// T_COLOR spočte rozdíl vyplněných otázek od celkového počtu a určí src obrázku

function t_color($count, $filled) {
	switch($count-$filled) {
		case 0: return "images/16x16_dot_g.gif"; break;
		case $count: return "images/16x16_dot_r.gif"; break;
		default: return "images/16x16_dot_b.gif"; break;
	}
}
*/

// ACTIVE

function active($stav) {
	if ($stav == 0) return "images/16x16/BulbOff.png";
	else return "images/16x16/BulbOn.png";
}

// SESSREG: jednoduchá registrace session proměnné jako globální

function sessreg($nazev){
	// Pro registraci proměnné $xy stačí zavolat sessreg('xy')
	// Změna oproti session_register:
	//		je-li session-proměnná již nastavena, pak její hodnota má přednost
	//		zatímco u session_register má přednost aktuální hodnota globální proměnné
	
	//if($r=isset($_SESSION[$nazev])) $GLOBALS[$nazev]=&$_SESSION[$nazev];
	//session_register($nazev);
	//return $r;
	if(isset($_SESSION[$nazev])) {$GLOBALS[$nazev]=&$_SESSION[$nazev];
		 //print "Session->GLOBALS[$nazev]=".$GLOBALS[$nazev];
		 return 1;};
	if(!$r=isset($GLOBALS[$nazev])) $GLOBALS[$nazev]="";
	//print "Zůstává ->GLOBALS[$nazev]=".$GLOBALS[$nazev]."<br />";
	$_SESSION[$nazev]=&$GLOBALS[$nazev];
	return $r;
};

/////////////////////////////////////////////////////////////////////////////
//                                                                         //
// SESSIONINPUT: Registrace proměnné předané v POST nebo GET jako session  //
//               POST má přednost                                          //
//               Není-li předána, zachovává se původní hodnota v $_SESSION //
//                                                                         //
/////////////////////////////////////////////////////////////////////////////

function sessioninput($name,$opt=0){
	$v='';
	if(array_key_exists($name,$_SESSION)) $v=$_SESSION[$name];
	if(array_key_exists($name,$_GET)) $v=$_GET[$name];
	if(array_key_exists($name,$_POST)) $v=$_POST[$name];
	$_SESSION[$name]=&$v;
	$v=stripsl($v,$opt);
	$GLOBALS[$name]=&$v;
	return $v;
}

// POSTGETREG: jednoduchá registrace globální proměnné předané pomocí POST nebo GET

function postgetreg($nazev,$opt=0)	{
	// Pro registraci proměnné $xy stačí zavolat sessreg('xy')
	if(isset($_POST[$nazev])) {$GLOBALS[$nazev]=stripsl($_POST[$nazev],$opt); return 1;};
	if(isset($_GET[$nazev])) {$GLOBALS[$nazev]=stripsl($_GET[$nazev],$opt); return 1;};
	if(!isset($GLOBALS[$nazev])){$GLOBALS[$nazev]=""; return 0;};
	return 1;
};

// HTMLSPEC: vylepšená funkce HTMLSpecialChars, která žere i pole

function htmlspec($a){
	if($a===null) return '';
	if(is_resource($a) || is_object($a)) return $a;
	if(is_array($a))
		{
			foreach($a as $arg => $v) $a[$arg]=htmlspec($v);
			return $a;
		}
	else return HTMLSpecialChars($a);
};

// HTMLSPECBR: vylepšená funkce HTMLSpecialChars, která žere i pole, navíc

function htmlspecbr($a){
	if($a===null) return '';
	if(is_resource($a) || is_object($a)) return $a;
	if(is_array($a))
		{
			foreach($a as $arg => $v) $a[$arg]=htmlspecbr($v);
			return $a;
		}
	else return nl2br(htmlspecialchars($a));
};

/*
	stripsl: vylepšená funkce stripslashes, která žere i pole a umožňuje převod na literály pouitelné přímo v databázi.
	$opt	=	typ parametru (1=text, 2=číslo, 3=date/datetime, 4=bit, dále trim, html)
					default(0) = sanitizace na html nebezpečné znaky
					raw = úmyslně bez sanitizace
*/
function stripsl($a,$opt=0,$len=0){
	global $form;
	if(is_array($a))
		{
			foreach($a as $arg => $v) $a[$arg]=stripsl($v,$opt,$len);
			return $a;
		}
	else {
		//debugitem("stripsl 1+ $opt ",$a);
		//if(get_magic_quotes_gpc()) $a=stripslashes($a);
		if($opt==='date' or $opt==='datetime' or $opt==='smalldatetime') $opt=3;
		//debugitem("stripsl 2+ $opt ",$a);
		
		// Následující řádky odstraňují vracejí zpět znaky <>, které explorer nahradil v TEXTAREA
		/*
		$a=str_replace('&lt;','<',$a);
		$a=str_replace('&gt;','>',$a);
		$a=str_replace('&amp;','&',$a);
		*/
		switch("$opt"){
			case 'trim':
				return charliteral(trim($a),$len);
			case 1: case 'char': case 'varchar': case 'nvarchar': case 'text': case 'ntext':
				return charliteral($a,$len);
			case 'guid': case 'uuid': case 'uniqueidentifier':
				return guidliteral($a);
			case 'tinyint':
				if($a>255) $a='';
				if($a<0) $a='';
				return intliteral($a);
			case 'smallint':
				if($a>32767) $a='';
				if($a<-32768) $a='';
				return intliteral($a);
			case 'int':
				if($a>2147483647) $a='';
				if($a<-2147483648) $a='';
				return intliteral($a,$len);
			case 'varbin': case 'varbinary': case 'hex':
				return varbinliteral($a);
			case '2': case 'bigint':
				$a=intliteral($a,$len);
				if(!is_numeric($a) OR bccomp($a,"9223372036854775807")>0 OR bccomp($a,"-9223372036854775808")<0) return 'NULL';
				return $a;
			case '3': case 'date': case 'datetime': case 'smalldatetime':
				return dateliteral($a);
			case '4': case 'bit': case 'checkbox':
				//debugitem('BIT value',$a);
				//if($a==0) $a=0; else $a=1;
				if($a) return 1; return 0;
				//return $a;
			case '5': // string with integer list
				return intliterallist($a);
			case '6': // HTML string
				return htmlvalue($a);
			case '0':
				break;
			case 'raw': return $a;
			// Při jakémkoli nesmyslu hodnotu převedu na číslo
			default: return intliteral($a,$len);
		};
		// Pokud má být získána hodnota bez konverze, musí se očistit od speciálních znaků, které by se mohly dostat do URL
		static $unsafe_characters = array('"', "'", '<', '>', '\\', '&', ';', '\0', '{', '}', '/');
		return str_replace($unsafe_characters,'',$a);
	};
};

// GETINPUT: získání proměnné předané pomocí POST nebo GET
// 30.11.2024 - Originální požadovaná hodnota bude vždy přítomna v poli $reginputs

function getinput($nazev, $dbLiteralType=0, $len=0)	{
	global $reginputs;
	if($dbLiteralType==='html'){
		if(isset($_POST[$nazev])) $dbLiteralType=1; else return 'NULL';
	}
	$r='';
	if(isset($_GET[$nazev])) {$r=$_GET[$nazev];};
	if(isset($_POST[$nazev])) {$r=$_POST[$nazev];};
	$reginputs[$nazev]=$r;
	return stripsl($r,$dbLiteralType,$len);
};

// REGINPUT: získání proměnné předané pomocí POST nebo GET, registrace globální proměnné
// 30.11.2024 - Současně zajišťuje, že žádaná proměnná (key) bude přítomna v poli $reginputs, ať byla předána v GET, POST nebo vůbec

function reginput($nazev, $dbLiteralType=0, $len=0)	{
	global $reginputs;
	$arr=explode(',',$nazev);
	if(count($arr)>1){
		foreach($arr as $prvek) reginput($prvek,$dbLiteralType,$len);
		return;
	}
	$nazev=trim($nazev);
	if($dbLiteralType==='html'){
		if(isset($_POST[$nazev])) $dbLiteralType=1; else return $GLOBALS[$nazev]='NULL';
	}
	$r='';
	if(isset($_GET[$nazev])) {$r=$_GET[$nazev];}
	if(isset($_POST[$nazev])) {$r=$_POST[$nazev];}
	$reginputs[$nazev]=$r;
	return $GLOBALS[$nazev]=stripsl($r,$dbLiteralType,$len);
};

// REGINPUT_SUFFIX: Funguje jako REGINPUT, jako první však má parametr, který se připojí k názvu zdrojové proměnné

function reginput_suffix($suffix,$nazvy,$dbLiteralType=0, $len=0){
	global $reginputs;
	$arr=explode(',',$nazvy);
	foreach($arr as $prvek){
		$r='';
		$prvek=trim($prvek);
		$source_name=$prvek."_$suffix";
		if(isset($_GET[$source_name])) {$r=$_GET[$source_name];}
		if(isset($_POST[$source_name])) {$r=$_POST[$source_name];}
		$reginputs[$prvek]=$r;
		$GLOBALS[$prvek]=stripsl($r,$dbLiteralType,$len);
	}
}

// REGINPUTS: volá funkci reginput opakovaně, seznam proměnných je v argumentu ve formě "p1:ty,p2,p3:typ"

function reginputs($s){
	$pp=explode(',',$s);
	foreach($pp as $p){
		$e=explode(':',$p);
		if(count($e)>1) reginput($e[0],$e[1]);
		else reginput($p);
	}
}

// EVALSTRING: Vyčíslí hodnotu stringu, který obsahuje jména proměnných

function evalstring(&$s){
	eval('global $'.implode(',$',array_keys($GLOBALS)).';');
	eval('$s = "'.addslashes($s).'";');
};

function printtableform($name,$data=null){
	global $PrintFormData;
	$PrintFormData=$data;
	print "
	<form name=$name action=index.php class=simple_input_form method=post>
	<table class=simple_input_form>";
};

function printrowinput($name,$type,$lab=""){
	global $PrintFormData;
	if($lab=="") $lab=$name;
	$val=@$PrintFormData[$name];
	if($type=="hidden"):
		print "
			<input type=$type name=$name value=\"".HTMLSpecialChars($val)."\"/>";
	elseif($type=="checkbox"):
		$val = $val?"checked":"unchecked";
		print "
			<tr><td>$lab</td><td><input type=$type align=left name=$name $val value=X /></td></tr>";
	else:
		print "
			<tr><td>$lab</td><td><input type=$type name=$name value=\"".HTMLSpecialChars($val)."\"/></td></tr>";
	endif;
};

class PageItem{
	var $name,$label,$header,$helptext,$input_type,$datatype,$width,$rows,$cols,$maxlength,
		$onchange,$onclick,$mandatory=0,$input_style,$input_attr,$id,
		$placeholder,
		$td_title,$td_style,$td_attr,$value,$htmlvalue,
		$tabname,
		$displayonly;
	function __construct($name=''){
		$this->name=$name??'';
		$this->label=$this->header=$this->name;
		$this->helptext='';
	}
};

function pageitem($name,$label,$header,$helptext,$input_type,$datatype,$width,$rows,$cols,$maxlength){
		global $pageitem_array;
		$o=new PageItem();
		$o->name=$name??'';
		$o->label=$label??'';
		$o->header=$header??'';
		$o->helptext=$helptext??'';
		$o->input_type=$input_type??'';
		$o->datatype=$datatype??'';
		$o->width=$width??'';
		$o->rows=$rows??'';
		$o->cols=$cols??'';
		$o->maxlength=$maxlength;
		$o->input_style='';
		//if($input_type=='text') $this->input_style='width:100%';
		//$this->input_size='150px';
		$o->displayonly=0;
		$o->td_style="";
		$o->td_attr="";
		$o->input_attr="";
		$o->value='';
		$o->htmlvalue='';
		//$this->ta_attr="rows=4 cols=60";
		$pageitem_array[$name]=&$o;
		$GLOBALS['pageitem_'.$name]=&$o;
	}

class PageTable{
	var $name,$title,$helptext;
};

function pagetable($name,$title,$helptext){
	global $pagetable_array;
	$o=new PageTable();
	$o->name=HTMLSpecialchars($name);
	$o->title=HTMLSpecialchars($title);
	$o->helptext=HTMLSpecialchars($helptext);
	$pagetable_array[$name]=&$o;
	$GLOBALS["pagetable_$name"]=&$o;
};

function th_tableinfo($tabname,$tha=''){
	global $pagetable_array;
	$item=$pagetable_array[$tabname];
	return "<th title=\"$item->helptext\" $tha>$item->title</th>";
};

function td2_value($name,$optval=null){
	global $cbxCenter;
	$cbxCenter=false;
	return td1_label($name).td1_value($name,'',$optval);
};

function td2_input($name,$inputname='',$optval=1,$moreHTML=''){
	global $cbxCenter;
	$cbxCenter=false;
	return td1_label(str_replace('[]','',$name)).td1_input($name,$inputname,$optval,$moreHTML);
};

function td1_label($name,$td=""){
	global $pageitem_array, $datarow, $mandatory_columns;
	$item=array_item($pageitem_array,$name,new pageitem($name));
	$helptext=htmlspecialchars($item->helptext);
	$man=(is_array($mandatory_columns) && in_array($name,$mandatory_columns))?'<span style=color:red;float:right;>*</span>':'';
	//$w=($item->width)?" width=$item->width":'';
	return "
	<td title=\"$helptext\" $td>$man".htmlspec($item->label)."</td>";
};

function td1_value($name,$td="",$optval=null,$moreHTML=''){
	global $pageitem_array, $datarow, $php_errormsg;
	$item=array_item($pageitem_array,$name,new PageItem($name));
	//if($name=='audit_date') debugitem('item',$item);
	$tds=$item->td_style?(" style=\"".$item->td_style."\" "):"";
	$val=$optval?$optval:nl2br(@$item->htmlvalue??'');
	if($item->datatype=='dateonly' || $item->datatype=='datetime' || $item->datatype=='smalldatetime' || $item->datatype=='date') $val=$item->value;
	$id=($item->id)?" id=\"$item->id\"":'';
	$td_title=$item->td_title;
	$td_title=htmlspecialchars($td_title?$td_title:$item->helptext);
	if($td_title) $td_title=" title=\"$td_title\"";
	if($item->input_type=='checkbox'){
		$ch = $val?' checked':'';
		//if(!$item->td_attr) $item->td_attr=' align=center';
		return "
		<td$td_title$tds $td $item->td_attr><input type=checkbox style=margin-top:2px name=$name value=$val disabled$ch>$moreHTML</td>";
	}
	if($item->input_type=='select'){
		$val=$item->value;
		if(!is_array($optval) AND $item->helptext){
			$optval=helptext_to_array($item->helptext);
		}
		if(is_array($optval)) $val=array_item($optval,$val,$val);
		if(is_array($val)) $val=array_item($val,1);
	}
	if(!$val) $val=htmlspecbr(array_item($datarow,$name));
	return "
	<td$id$td_title$tds $td $item->td_attr>$val$moreHTML</td>";
};

function th_pageitemheader($name,$td=""){
	global $pageitem_array, $datarow;
	$a=explode(',',$name);
	if(count($a)>1){
		$r='';
		foreach($a as $name) $r .= th_pageitemheader($name,$td);
		return $r;
	}
	if(array_key_exists($name,$pageitem_array)){
		$item=$pageitem_array[$name];
		$helptext=HTMLSpecialChars($item->helptext);
		$val=HTMLSpecialChars($item->header);
		$w=($item->input_type=='checkbox')?'':"width=$item->width";}
	else {
		$helptext='The column description is missing for this page';
		$val=$name;
		$w='';
	}
	//print "th_helptext:$helptext<br />";
	return "
	<th title=\"$helptext\" $w $td>$val</th>";
};

function td1_input($name,$inputname='',$optval=1,$moreHTML=''){
	global $pageitem_array,$datarow,$tag_select,$page_readonly,$cbxCenter;

	// Otestování, zda na stránce nebo v načtených datech není příznak editable
	
	$rn=str_replace('[]','',$name);
	if(!$inputname) $inputname=$name;
	//$item=$pageitem_array[$rn];
	$item=array_item($pageitem_array,$rn,new pageitem($rn));
	$itype=$item->input_type;
	// Vložení kalendáře pro editaci data
	if($item->datatype=='date' || $item->datatype=='dateonly')
		return "<td>".HTML_Calendar($inputname,$datarow[$rn],$item->mandatory)."$moreHTML</td>";
	if($item->datatype=='datetime' || $item->datatype=='smalldatetime')
		return "<td>".HTML_Calendar($inputname,$datarow[$rn],$item->mandatory,true)."$moreHTML</td>";
	$readonly=$page_readonly?' readonly':'';
	if(isset($datarow['editable'])){
		if(!$datarow['editable']) $readonly=' readonly';
	}
	
	// Toto byla chyba
	
	/*
	if($readonly && $itype!='select'){
		return td1_value($name);
	}
	*/
	
	//
	
	if($item->displayonly)  $readonly=' readonly';
	$dis=$readonly?" disabled":"";
	$helptext=htmlspec($item->helptext);
	$val=@$datarow[$rn];
	$checked=$wi="";

	// přednastavím zarovnání vpravo u číselných typů	

	if(/*!($ins=$item->input_style) && */($itype=='text')){
		if(in_array($item->datatype,array('int','smallint','bigint','dec','decimal','number','tinyint'))){
			$item->input_style='text-align:right;max-width:80px;';
			if($val>=1000 and $val<2140000000 and in_array($item->datatype,array('int','smallint','bigint','number'))) $val=number_format($val,0,'.',' ');
			//$wi=80;
		}
	}

	$tds=$item->td_style?(" style=\"".$item->td_style."\" "):"";
	$ins='';
	if($item->input_style) $ins="style=$item->input_style";
	$tda=$item->td_attr;
	$maxl=$item->maxlength?" maxlength=$item->maxlength":'';
	
	$onchange=$item->onchange;
	if(!$onchange and ($item->datatype=='date' or $item->datatype=='dateonly' or $item->datatype=='datetime' or $item->datatype=='smalldatetime')) $onchange="return check_date(this,$item->mandatory);";
	if(!$onchange) $onchange="data_changed=true;";
	if($onchange) $onchange=" onChange=".htmlliteral($onchange);
	$onclick=$item->onclick?" onClick=".htmlliteral($item->onclick):'';
	
	if($itype=="select"){
		// V případě selectu musí být předáno pole $optval, nebo se načte z helptextu
		if(!$inputname) $inputname=$name;
		if(!is_array($optval)) $optval=helptext_to_array($helptext);
		// Následující odmaskovaný příkaz způsoboval nulovou šířku selectů
		//if(!$ins) $ins='style=\"width:100%\"';
		//return "<td $tda>".html_select($inputname,$optval,$val,"$tda title=\"$helptext\" $onchange $dis")."</td>";
		if($readonly)
			return "<td $tda>".html_select($inputname,$optval,$val,"title=\"$helptext\" $onchange $dis $ins $item->input_attr")
				."<input type=hidden name=\"$inputname\" value=\"$val\">$moreHTML";
		else{
			return "<td $tda>".html_select($inputname,$optval,$val,"title=\"$helptext\" $onchange $dis $ins $item->input_attr",$item->placeholder?:true)."$moreHTML";
		}
	};
	if($itype=="radio"){
		// V případě radio musí být předáno pole $optval
		if(!$inputname) $inputname=$name;
		$radio="";
        foreach($optval as $v=>$txt){  
            $checked=($v==$val)?"checked":"";
            $radio .= "<span style=\"white-space:nowrap\"><input type=radio id=\"$inputname"."_$v\" name=\"$inputname\" value=\"$v\" $checked title=\"$helptext\" $onchange $dis $ins>$txt</span>";
        }
		return "<td $tda>$radio$moreHTML</td>";
	};
	if ($itype=="checkbox") {
		$checked=$val?"checked":"unchecked";
		$val=$optval;
		if($cbxCenter && !$tda) $tda="align=center";
		if($readonly){
			$hi=($checked=='checked')?"<input type=hidden name=$inputname value=\"".@htmlspec($val)."\">":"";
			return "<td title=\"$helptext\" $tds $tda><input type=\"checkbox\" $checked$maxl disabled >$hi$moreHTML</td>";
		} else
			return "<td title=\"$helptext\" $tds $tda><input name=$inputname$dis type=\"checkbox\" $checked$maxl value=\"".@htmlspec($val)."\" $onclick $onchange $readonly $item->input_attr>$moreHTML</td>";
	};
	if($item->placeholder===' ') debugitem("JO");
	$placeholder=($item->placeholder OR $item->placeholder===' ')?"placeholder=".htmlliteral($item->placeholder):"";
	if($itype=="textarea"){
		//debugitem("PH",$placeholder);
		$cols=($item->cols)?" cols=$item->cols":'';
		$tdh=($item->rows)?" height=".(18*$item->rows):'';
		$tdh=''; // 14.2.2009: Předchozí nastavení výšky způsobovalo, že pole nebylo vidět celé.
		$tdw=" width=$item->width";
		if($ins) $ins .= ";width:100%"; else $ins="style=\"width:100%;\"";
		//$ins .= ";height:20"; // Ve FF způsobovalo, že byl vidět vždy jen jeden řádek
		//debugitem('textarea',"<textarea name=$inputname$dis rows=$item->rows $maxl $ins $onchange/>");
		$r="<td title=\"$helptext\" $tds$tdh $tda><textarea $placeholder autoresize=yes id=$inputname $dis name=\"$inputname\" $cols $maxl $ins $onchange $dis>".@htmlspec($val)."</textarea>$moreHTML</td>";
		//debugitem($item->name,$r);
		return $r;
	};
	if(!$wi)
		$wi=($item->datatype=='date')?'62':'100%';
	$ins="style=\"width:$wi;$item->input_style;\"";
	$td_title=$helptext?" title=\"$helptext\"":'';
	$r="<td$td_title $tds $tda><input id=$inputname $placeholder name=$inputname $readonly type=\"$item->input_type\" $checked$maxl value=\"".@htmlspec($val)."\" $ins $item->input_attr$onchange>$moreHTML</td>";
	//debugitem($item->name,$r);
	return $r;
};

// TD_PERCENT: Zobrazí buňku s procentuálním zobrazením čísel

function td_percent($count,$fill,$confirmed=NULL,$printtext=1){
	$blue = "#1D5892";
	$green = "#468729";
	$red = "#D60000";
	if($confirmed===NULL){
		if($count==0) return "<td></td>";
		$prc=round(100*$fill/$count,0);
		if($prc==100 && $fill!=$count) $prc=99;
		$proc=$prc."%";
		if($prc<0 or $prc>100) return "<td><div title=\"$proc\" class=pbar style=\"color:$red; background-color:white;\"></div></td>";
		$bg=$blue;
		if($prc==0) $bg=$red; else if($prc==100) $bg=$green;
		return "<td align=center bgcolor=$bg style=\"color:white;\">$proc</td>";
	} else
	{	
		if($count<=0) return "<td></td>";
		
		// Následující kód sice není možná elegantní, ale je přehledný.
		// Řeší všechny možné kombinace
		
		
		$p1 = $confirmed/$count;
		$p2 = ($fill-$confirmed)/$count;
		$p3 = ($count-$fill)/$count;
		
		if($p1<0 or $p1>1 or $p2<0 or $p2>1 or $p3<0 or $p3>1) return "<td><div class=pbar style=\"color:$red; background-color:white\">Bad parameters</div></td>";
		
		$pr1 = (round(100*$p1,0));
		$pr2 = (round(100*$p2,0));
		$pr3 = (round(100*$p3,0));
		$konst = 100;
		if (($pr1 + $pr2 + $pr3) > $konst) {
			$max = max(max($pr1, $pr2), $pr3);
			
			if ($max == $pr1) $pr1 += -1;
			else if ($max == $pr2) $pr2 += -1;
			else if ($max == $pr3) $pr3 += -1;
		}
		
		//if($pr1!=100) debugitem("PR $pr1 $pr2 $pr3 count=$count, fill=$fill");
		
		$s="<div class=pbar style=\"color:$red; background-color:white\">Unexpected combination ".($pr1)."%, ".($pr2)."%, ".($pr3)."%</div>";
		
		// 1) GGG Všechno je potvrzeno
		
		if ($p1==100)
			$s="<div title=\"".($pr1)."%\" class=pbar style=\"background-color:$green; min-width:100px;\"></div>";
		
		// 2) RRR = nic není vyplněno
		
		elseif ($fill==0) $s= "<div title=\"".($pr3)."%\" class=pbar style=\"background-color:$red; width:100px;\"></div>";
		
		// 3) BBB = vše je částečně vyplněno
		
		elseif ($confirmed==0 and $count==$fill)
			$s= "<div class=pbar title=\"".($pr2)."%\" style=\"background-color:$blue; width:100px;\"></div>";
		
		// 4) GBR = všechny stavy
		elseif ($p1>0 and $p2>0 and $p3>0)
			$s= "<div title=\"".($pr1)."%\" class=pbar style=\"background-color:$green; width:$pr1"."px\"></div><div title=\"".($pr2)."%\" class=pbar style=\"background-color:$blue; width:$pr2;\"></div><div title=\"".($pr3)."%\" class=pbar style=\"background-color:$red; width:$pr3\"></div>";
		
		// 5) G+B
		elseif ($p3==0 && $pr1)
			$s= "<div title=\"".($pr1)."%\" class=pbar style=\"background-color:$green; width:$pr1"."px\"></div><div title=\"".($pr2)."%\" class=pbar style=\"background-color:$blue; width:$pr2;\"></div>";
		
		// 7) G+R
		elseif ($p2==0 && $pr1)
			$s= "<div title=\"".($pr1)."%\" class=pbar style=\"background-color:$green; width:$pr1"."px\"></div><div title=\"".($pr3)."%\" class=pbar style=\"background-color:$red; width:$pr3;\"></div>";
		
		// 9) B+R
		
		elseif ($p1==0 && $pr2) $s= "<div title=\"".($pr2)."%\" class=pbar style=\"background-color:$blue; width:$pr2"."px\"></div><div title=\"".($pr3)."%\" class=pbar style=\"background-color:$red; width:$pr3;\"></div>";
		
		//debugitem("s",$s);
		
		$pr1=$printtext?"<div style=position:absolute;z-index:2;width:104px;color:white;>$pr1%</div>":"";
		return "<td style=\"vertical-align: top; text-align: center; border: 0px; padding: 0px;\">$pr1<div style=\"border: 1px solid black; width: ".($konst+2)."px;\">$s</div></td>";
	};
};

//<div style=\"width: 100px; text-align: center; position: absolute; left:297px; color: white;\">$pr1&nbsp;$pr2&nbsp;$pr3</div>


// SQLARRAY: Funkce přečte result set a připraví z něj jednoduché indexované pole
// Přídavný parametr true způsobí, že se čte z již otevřeného result setu

function sqlarray($p=null,$continue=0){
	global $dbms,$dbquery;
	if(!isset($p)) $p=$dbquery;
	$continue=(is_resource($p) || is_object($p));
	if(!$continue) $res=sqlrun($p); else $res=$p;
	$r=array();
	while($d=fetch($res)){
		//debugitem('Sqlarray fetch',$d);
		$r[$d[0]]=$d[1];
	}
	next_result($res);
	if($continue) return $r;
	free_result($res);
	return $r;
}

// SQLFIRSTROW: Funkce přečte první řádek resultu do jednoduchého pole
// Pokud není zadán parametr (SQL příkaz), pak čte z běžícího query

function sqlfirstrow($p=null){ // Zpravidla je v parametru zadán příkaz
	global $dbms,$dbquery;
	if(!isset($p)) $p=$dbquery; // Není-li zadán, tak se pokračuje ve čtení stávajících result setů
	$continue=(is_resource($p) or is_object($p));
	if(!$continue) $dbquery=$res=sqlrun($p); else $res=$p;
	//debugitem('res',$res);
	if($d=fetch($res)){
		next_result();
		if($continue) return $d;
		cleanup_result();
		// free_result($res); // Původní příkaz
		return $d;
	}
	next_result();
	return array();
}

// SQLARRAY2: Funkce přečte result set a připraví z řádků dvojrozměrné pole indexované
// První položka je unikátní a je indexem první úrovně
// Přídavný parametr se nepoužívá

function sqlarray2($p=null,$continue=0){
	global $dbms,$dbquery;
	if(!isset($p)) $p=$dbquery;
	if(is_resource($p) or is_object($p)) {$res=$p; $continue=1;} else $res=sqlrun($p);
	//if(!$continue) $res=sqlrun($p); else $res=$p;
	$r=array();
	while($d=fetch($res)) $r[$d[0]]=$d;
	next_result($res);
	if($continue) return $r;
	free_result($res);
	return $r;
}

// SQLARRAY3: Funkce přečte result set a připraví z řádků trojrozměrní pole
// Indexem prvního rozměru je první sloupec, který není unikátní
// Druhý rozměr obsahuje pole se skupinou řádků, které mají stejnou hodnotu v prvním sloupci
// Třetí rozměr je řádek s daty

function sqlarray3($p=null){
	global $dbquery;
	if(!$p) $p=$dbquery;
	$continue=$i=0;
	if(is_resource($p) or is_object($p)) {$res=$p; $continue=1;} else $res=sqlrun($p);
	$r=array();
	while($d=fetch($res)){
		$key=$d[0];
		if(array_key_exists($key,$r)) array_push($r[$key],$d);
		else $r[$key]=array($d);
	}
	next_result($res);
	if($continue) return $r;
	free_result($res);
	return $r;
}

// SQLARRAY_SIMPLE: Funkce přečte result set a připraví z řádků prosté pole

function sqlarray_simple($p=null){
	global $dbquery;
	if(!$p) $p=$dbquery;
	$continue=$i=0;
	if(is_resource($p) or is_object($p)) {
		$res=$p; $continue=1;
	} else
		$res=sqlrun($p);
	$r=array();
	while($d=fetch($res)) $r[$i++]=$d;
	next_result($res);
	if($continue) return $r;
	free_result($res);
	return $r;
}

// FETCH_DATAROW: fetchne řádek s daty a zapíše hodnoty do proměnné $pageitems
// 31.12.2010 - Vytváří celý objekt PageItem pro každou načtenou položku
// 21.09.2011 - Pro nově vložené položky doplňuje i header, label a helptext
function fetch_datarow($rs=null){
	global $datarow, $pageitem_array, $htmldatarow, $dbquery;
	if(!$rs) $rs=$dbquery;
	if($datarow=fetch($rs)) {
		//debugdatarow();
		$htmldatarow=htmlspec($datarow);
		foreach($datarow as $name => $value){
			unset($pi);
			if(is_array($pageitem_array) && array_key_exists($name,$pageitem_array))
				$pi=&$pageitem_array[$name];
			else{
				$pi=new PageItem();
				$pi->name=$name;
				$pi->helptext="The column description has not been found";
				$pi->header=$name;
				$pi->label=$name;
				$pageitem_array[$name]=&$pi;
			}
			$value0=$value ?? '';
			$GLOBALS["pageitem_$name"]=&$pi;
			$type='unknown';
			if(isset($pi->datatype) & $value!=NULL){
				$type=$pi->datatype;
				if(($type=='date') || ($type=='dateonly')){
					$value=substr($value,8,2).'.'.substr($value,5,2).'.'.substr($value,0,4);
					$datarow[$name]=$value;
				} else
				if($type=='datetime'){
					$value=substr($value,8,2).'.'.substr($value,5,2).'.'.substr($value,0,4).substr($value,10);
					$datarow[$name]=$value;
				} else
				if($type=='smalldatetime'){
					$value=substr($value,8,2).'.'.substr($value,5,2).'.'.substr($value,0,4).substr($value,10,6);
					$datarow[$name]=$value;
				}
			}
			if($type=='decimal'){
				$sv=(string)$value;
				if($sv[0]==".") $datarow[$name]="0$value";
			}
			$pi->value=$value;
			$pi->htmlvalue=HTMLSpecialChars($value0);
		};
		return 1;
	};
}

/*
	HTML_SELECT: vrátí HTML syntaxi selectu
*/
function html_select($name,$values,$selectedvalue="~~--~~",$attributes="",$addSelectedValue=true){
	global $page_readonly;
	static $nodebug=1;
	$n=htmlliteral($name);
	$r=$selectedStyle=$selectedText="";
	if($selectedvalue=="~~--~~"){
		$selectedvalue=@array_keys($values)[0];
	}
	$selectedvalue=(string)$selectedvalue;
	$style=$selected='';
	$selectedOv=htmlliteral($selectedvalue);
	// 18.08.2015: Pokud vybrana hodnota neexistuje, tak ji vlozim, aby se zapisem neztratila
	if($addSelectedValue && (!is_array($values) || !array_key_exists($selectedvalue,$values))){
		// Vyjimka, "NULL" hodnota se nevkládá, pokud existuje prázdná
		if(!($selectedvalue=='NULL' and array_key_exists('',$values))){
			//debugitem("Vkládám chybějící hodnotu $selectedvalue", $values);
			$empty_option=(is_string($addSelectedValue) AND !$selectedvalue)?$addSelectedValue:$selectedvalue;
			$r = "<option value=\"$selectedvalue\" selected style=\"color:red\">$empty_option</option>";
		}
	}
	if(is_array($values)) foreach($values as $optionvalue => $option){
		$optionvalue=(string)$optionvalue;
		$selected=$optionTitle='';
		if(is_array($option)){
			//debugitem('option',$option);
			// Nastaveni textu
			if(array_key_exists('optiontext',$option)) $optiontext=$option['optiontext'];
			elseif (array_key_exists('name',$option)) $optiontext=$option['name'];
			else $optiontext="$optionvalue optiontext";
			// Nastaveni titulku
			if($optionTitle=array_item($option,'optiontitle')) $optionTitle=" title=".htmlliteral($optionTitle);
			//$optiontext=array_key_exists('optiontext',$option)?$option['optiontext']:"$optionvalue optiontext";
			// Nastaveni stylu
			$style=array_key_exists('backgroundcolor',$option)?"background-color:$option[backgroundcolor];":"";
			$style .= array_key_exists('color',$option)?"color:$option[color];":"";
			if(array_key_exists('style',$option)) $style=$option['style'];
			if(array_key_exists('selected',$option)){
				//debugitem('exists');
				$selected=$option['selected']?'selected':'';
			} // else debugitem("not exists $selectedvalue",$optionvalue);
		} else {
			$optiontext=$option;
		}
		$ov=htmlliteral($optionvalue);
		$ot=htmlspecialchars($optiontext??'');
		//debugitem('OT',$ot);
		if($style) $style="style=\"$style\"";
		//debugitem('selected',$selected);
		if($optionvalue==$selectedvalue){
			$selected='selected';
			$selectedText=$ot;
			$selectedOv=$ov;
		}
		if($selected) $selectedStyle=$style;
		$r .= "
		<option value=$ov $selected $style$optionTitle>$ot</option>";
		//debugitem('options',$r);
	};
	$id=(strpos($attributes,"multiple")===false)?"id=\"$name\"":"";
	if($page_readonly) {
	   $r = "
		<select $id name=\"$name\" $attributes disabled $selectedStyle>$r</select>
		<input type=hidden id=\"hidden_$name\" name=\"$name\" value=$selectedOv>";
	} else
		$r = "<select $id name=\"$name\" $attributes $selectedStyle>$r</select>";
	return $r;
}

function html_radio($name,$value,$selectedvalue,$attributes=''){
	$v=htmlspecialchars($value);
	$checked=($value==$selectedvalue)?' checked':'';
	return "<input type=radio name=\"$name\" value=\"$v\"$checked $attributes>";
}

function html_textarea($name,$value,$attr=''){
	if(!$attr) $attr="id=\"$name\"";
	return "<textarea name=\"$name\" $attr>".htmlspecialchars($value)."</textarea>";
};

// Funkce vytvoří syntaxi multiselectu z předaného pole

function dbMultiselect($array,$name,$readonly=false){
	$r='';
	$cbxs=$options=$forAddCbxs="";
	$forAdd=0;
	foreach($array as $index=>$item){
		$style=$item['style'];
		if($style) $style = "style=\"$style\"";
		$label=$item['name'];
		if($item['selected']){
			if($readonly){
				$cbxs .= "<div $style><input name=\"$name"."[]\" type=hidden value=\"$index\" >$label</div>";
			} else
				$cbxs .= "<div $style><input id=\"$name"."_$index\" name=\"$name"."[]\" type=\"checkbox\" checked value=\"$index\" style=\"margin:0px 3px 1px 3px;\">$label</div>";
		} elseif(!$readonly){
			$forAdd++;
			$forAddCbxs .= "<div $style><input id=\"$name\" name=\"$name"."[]\" type=\"checkbox\" value=\"$index\" style=\"margin:0px 3px 1px 3px;\">$label</div>";
			$options .= "<option value=\"$index\" $style>$label</option>";
		}
	}
	if($forAdd<4) return "$cbxs$forAddCbxs";
	if($options) $options = "<select id=\"dropdownchecklist_$name\" name=\"$name"."[]\" multiple class=\"dropdownchecklist\">$options</select>";
	return "$cbxs$options";
}

function debugitem($label,$text='',$utf8=false){
	global $debugitems, $debugmode;
	if(!$debugmode) return;
	//print "<br>MAIN DEBUG $label: "; print_r($text);
	//print "<br>MAIN DEBUG $label: is_resource=".is_resource($text);
	//print "<br>MAIN DEBUG $label: is_array=".is_array($text);
	if(!is_array($debugitems)) $debugitems=array();
	if(is_array($text)) foreach($text as $i=>$item) if(is_string($item)) $text[$i]=htmlspec($item);
	$typ='';
	$p=new stdClass();
	$p->label=$label;
	//print "<br>MAIN DEBUG $label: resource 2=".is_resource($text);
	$p->text=$text;
	$p->utf8=$utf8;
	$p->isres=false;
	if(is_resource($p->text)){
		$p->isres=true; // Oprava chyby PHP, kdy se ztrácí vlastnost resource
		$p->text="$p->text";
	//print "<br>MAIN DEBUG $label: p-text resource=".is_resource($p->text);
	}
	array_push($debugitems,$p);
	rtn: return;
}

function debugget(){
	global $debugmode;
	debugitem('GET',$_GET);
	if(isset($_POST)) debugitem('POST',$_POST);
	if(isset($_SESSION)) debugitem('SESSION',$_SESSION);
	if(isset($_FILES) && count($_FILES)) debugitem('FILES',$_FILES);
	if(isset($_COOKIE)) debugitem('COOKIE',$_COOKIE);
}

function debugg($name){debugitem($name,array_item($GLOBALS,$name,'Undefined variable'));}
function debugdatarow($globalVariable='datarow'){
	$data=$GLOBALS[$globalVariable];
	array_unset_numeric_keys($data);
	debugitem($globalVariable,$data);
}
function debugtime($label=''){debugitem("TIME $label",date('H:i:s'));}

function array_unset_numeric_keys(&$array){
	foreach($array as $key=>&$val){
		if(is_array($val))
			array_unset_numeric_keys($val);
		else
			if(is_numeric($key)) unset($array[$key]);
	}
}

/*
	Funkce addArrayKeysInfo
	Prida pro ucely debugu na zacatek pole informace o jeho klicich, pokud nejsou numericke a je vic nez jeden
*/
function addArrayKeysInfo(&$a,$nk,$recursion){
	foreach($recursion as &$rr) if($a===$rr) return; // Rekurse
	if(is_array($a)){
		if(array_key_exists('NESTED_ARRAYS',$a)) return $a;
		$keyList=array();
		$keyCount=0;
		foreach($a as $k=>&$i){
			if(!is_numeric($k) && is_array($i)) {
				$ic=count($i);
				$keyList[$k] = $ic;
				$recursion[] = &$a;
				addArrayKeysInfo($a[$k],"$nk/$k",$recursion);
				$keyCount++;
			} 
		}
		if($keyCount and $keyList)
			$a=array('NESTED_ARRAYS'=>$keyList)+$a;
	}
	return;
}

function debugprint($noprint=false){
	global $debugitems,$debugmode,$debugContent;
	if(is_array($debugitems) and (count($debugitems)>0) && $debugmode){
		$debugContent = '
<DIV><H1>DEBUG:</H1>';
		foreach($debugitems as $index=>$item){
			$val=$item->text;
			if($val===null) $val='--NULL--';
			if($val===false) $val='--FALSE--';
			if($val===true) $val='--TRUE--';
			if(is_resource($val)) $val="$val";
			$debugContent .= "<br /><span style=\"color:blue;font-weight=bold\">$item->label: </span>";
			if(is_array($val) or is_object($val)){
				$recursion=array();
				addArrayKeysInfo($val,$item->label,$recursion);
				ob_start();
				var_export($val);
				$val=nl2br(ob_get_contents());
				if($item->utf8) $val=from_utf8($val);
				$s=str_replace('<br />','<br/>',$val);
				$s=str_replace('  ','&nbsp;',$s);
				$s=str_replace("\r\n",'<br/>',$s);
				ob_clean();
				$debugContent .= $s;
			} else{
				//print "BACHA $val !";
				if($item->isres){
					$debugContent .= "$val";
				} else {
					if(is_resource($val) or empty($val) or strpos(gettype($val),'resource')!==false){
						$debugContent .= "$val";
					}else{
						//$val="$val";
						//$debugContent .= nl2br(HTMLSpecialChars(($item->utf8?from_utf8($val):$val)));
						$debugContent .= nl2br(HTMLSpecialChars($val));
					}
				}
			}
		};
		$debugContent .= '</DIV>';
	};
	if(!$noprint) print $debugContent;
	return $debugContent;
}

function debugerror($context){
	global $php_errormsg;
	if($php_errormsg){
		debugitem("ERROR $context",$php_errormsg);
		$php_errormsg='';
	}
}

function private_file($fn){
	global $private_folder, $result_wwwsession;
	return "$private_folder/$result_wwwsession[user_login]_$fn";
}

function initsession(){
	global $result_wwwsession,$page,$SID,$lang,$current_review,$REMOTE_USER_NAME,$debugmode,$jsyntax
		,$right_debug,$right_sysadmin,$right_orgadmin,$right_revedit,$right_profadmin,$right_profadmin_enabled
		,$developer_mode,$right_developer,$rev_currency_code,$org_currency_code,$currency_code_mismatch
		,$cm_cat_max,$cat1_in_context,$show_request_duration,$statistics_cat2;
	
	// Odhlášení uživatele
	//free_result($r);
	$page=getinput('page');
	if ($page == "logout") {
		sqlrun("delete from wwwsession where wwwsession = '$SID'");
	};
	
	$rms=charliteral($REMOTE_USER_NAME);
	//if (!($r = sqlpagerun("set nocount on execute init_wwwsession '$SID',0,'$lang',@ntlm_name=$rms",0))) fatal_error("execute init_wwwsession '$SID'"); 
	if (!($r = sqlrun("set nocount on execute init_wwwsession '$SID',0,'$lang',@ntlm_name=$rms",0))) fatal_error("execute init_wwwsession '$SID'"); 
	
	$result_wwwsession=htmlspec(fetch($r));
	free_result($r);
	// Ošetříme stav, kdy user není přihlášen
	if ($result_wwwsession[0]<0):
		require_once(require_file("login.php"));
		login_screen();
	endif;
	$current_review=intliteral($result_wwwsession['crr_review']);
	$cm_cat_max=$result_wwwsession['cm_cat_max'];
	$statistics_cat2=$result_wwwsession['statistics_cat2'];
	$cat1_in_context=$result_wwwsession['cat1_in_context'];
	$right_debug=$result_wwwsession['right_debug'];
	$right_sysadmin=$result_wwwsession['right_sysadmin'];
	$right_orgadmin=$result_wwwsession['right_orgadmin'];
	$right_revedit=$result_wwwsession['right_revedit'];
	$right_developer=$developer_mode?$right_debug:0;
	$right_profadmin_enabled=$result_wwwsession['right_profadmin_enabled'];
	$right_profadmin=$result_wwwsession['right_profadmin'];
	$rev_currency_code=$result_wwwsession['rev_currency_code'];
	$org_currency_code=$result_wwwsession['org_currency_code'];
	$show_request_duration=$result_wwwsession['show_request_duration'];
	if(!$result_wwwsession['right_debug']) $debugmode=0;
	$currency_code_mismatch=$result_wwwsession['currency_code_mismatch'];
	//debugg('result_wwwsession');
	$jsyntax .= "
var rev_stat='$result_wwwsession[rev_stat]';
var rev_stat_locked=$result_wwwsession[rev_stat_locked];";
}

function sendAlert($time) {
	global $T_TIMEOUT_WARNING;
	print "<script>setTimeout(\"alert('$T_TIMEOUT_WARNING')\", $time);</script>";
}

// V podle výsledku $x mod 2 vrací světlý nebo tmavý styl
function selectColor($x) {
	if ($x%2 == 0) return "tr_even";
	else return "tr_odd";
}

// EVEN_ODD: vrací class "even" nebo "odd"
function even_odd(&$n, $inc=1){
	if ($inc == 1) $n = (int)$n+1;
	return ($n%2)?'odd':'even';
}

function even_odd2(&$n, $inc=1){
	if ($inc == 1) return (++$n%2)?'odd2':'even2';
	else return ($n%2)?'odd2':'even2';
}

function picturebutton($pict,$onclick,$title='',$text='', $style='', $attr=''){
	//$title=$title?"title=".htmlliteral($title):'';
	//$onclick=$onclick?"onclick=".htmlliteral($onclick):'';
	//$padding=$text?'2px 4px 0px 1px':'2px 0px 1px 1px';
	$r=new PictureButton($pict,$onclick,$text);
	if($title) $r->setTitle($title);
	if($attr) fatal_error('SW potřebuje údržbu','Použit nepodporovaný parametr funkce picturebutton');
	$r->addStyle($style);
	return $r;
	//return "<button $attr $onclick $title style=\"padding:$padding; height: 25px;$style;\"><img src=\"$pict\">".htmlspecialchars($text).'</button>';
}

function htmlvalue($v){return '"'.HTMLSpecialChars($v ?? '').'"';}


// NORMALIZE_PERCENT
// Funkce upraví prvky pole lineárně tak, aby bylo dosaženo požadovaného celočíselného součtu
// Hodí se pro převod hodnot na graf

function normalize_percent($a,$base){
	global $normalize_percent_sum, $normalize_percent_raw;
	$normalize_percent_sum=$t=0;
	$normalize_percent_raw=array();
	$d=0;//($a[1]==145);
	if($d) debugitem('A',$a);
	foreach($a as $i=>$p) $normalize_percent_sum += $p;
	if(!$normalize_percent_sum) return $a;
	foreach($a as $i=>$p) {
		$normalize_percent_raw[$i]=$raw=$base*$p/$normalize_percent_sum;
		$x=ceil($raw);
		$a[$i] = $x;
		$t += $x;
	}
	if($d) debugitem("pred",$a);
	arsort($a);
	if($d) debugitem("Po arsort",$a);
	$diff=$t-$base;
	if($d) debugitem("diff",$diff);
	$i0=0;
	if($diff)
		foreach($a as $i=>$x) {
			if($x>1) {
				$a[$i]=$x-1;
				if(--$diff){
					$i0=$i;
					continue;
				}
			}
			else {
				$a[$i0]=$a[$i0]-$diff;
			}
			break;
		}
	ksort($a);
	if($d) debugitem('return',$a);
	return $a;
}

/*
function tr_fixed_size($a,$style='style=height:0'){
	if(is_string($a) && count(explode(',',$a)>1)) $a=explode(',',$a);
	$args=func_get_args();
	$r='';
	if(is_array($a))
		foreach($a as $w) $r .= "<td width=$w></td>";
	else{
		foreach($args as $w) $r .= "<td width=$w></td>";
		return "<tr $style>$r</tr>";
	}
	return "<tr $style>$r</tr>";
}
*/

function tr_fixed_size($a,$style='style=display:none'){
	if(is_string($a)){
		$arr=explode(',',$a);
		if(count($arr)>1) $a=explode(',',$a);
	}
	$args=func_get_args();
	$r1=$r2='';
	if(is_array($a))
		foreach($a as $w){
			$r1 .= "<col style=\"width:$w;\">";
			$r2 .= "<td width=$w style=\"width:$w;min-width:$w;\"></td>";
		}
	else{
		foreach($args as $w){
			$r1 .= "<col width=$w style=\"width:$w;min-width:$w;\">";
			$r2 .= "<td></td>";
		}
	}
	//return "<colgroup>$r1</colgroup><tbody><tr class=fixedWidth>$r2</tr></tbody>";
	return "<colgroup>$r1</colgroup>";
}


function from_utf8($v){global $charset;return iconv("utf-8",$charset,$v);}

function include_tables($tns){
	global $lang;
	$tlist=explode(',',$tns);
	foreach($tlist as $tn){
		include "phpgen/$lang/T_$tn.php";
	}
}

/* CBX_AUTOSAVE: generuje bezejmenný checkbox a skryté pole.
	Výchozí hodnoty mají jména pro vlastnost autoatického ukládání autosave:
	id=hidden_autosave name=autosave
	Použití:
	- globální proměnná se načte ze session: sessionput('autosave');
	- skryté pole se generuje vždy, aby bylo možno poznat, zda na formuláři bylo
	28.01.2014 - funkce upravena i pro jiné názvy proměnných
*/
function cbx_autosave($name='autosave',$label=''){
	global $T_AUTOSAVE, $page_readonly;
	$keyval=&$GLOBALS[$name];
	if($label=='') $label=$T_AUTOSAVE;
	if($page_readonly or getinput('page_readonly') ) return '';
	$checked=$keyval?'checked':'';
	$val=$GLOBALS[$name]?1:0;
	@list($text,$title)=explode(';',$label);
	return "<input id=hidden_$name type=hidden name=$name value=$val>
	<label title=\"$title\" for=cbx_$name><input id=cbx_$name type=checkbox value=1 $checked onclick=\"getelement('hidden_$name').value=this.checked?'1':'0';\">$text</label>";
}

//
// SQLPARAMETERS: Funkce sestaví string pro SQL parametry ve tvaru "@par1=$par1, @par2=$par2 ...
// Předaným argumentem je seznam jmen parametrů oddělených čárkami, které musí být globální proměnné
// Je-li proměnnou pole, pak se slepí ve string-literál oddělený čárkami
//
function sqlparameters($list){
	$r='';
	$pp=explode(',',$list);
	foreach($pp as $p){
		$p=trim($p);
		if(!$p) continue;
		$val=array_key_exists($p,$GLOBALS)?$GLOBALS[$p]:'0';
		if(is_array($val)){
			$s='';
			foreach($val as &$v){
				if(is_array($v)) fatal_error("array in sql-parameter");
				if(substr($v,0,1)=="'" and substr($v,-1,1)=="'"){
					$v=str_replace("''","'",substr($v,1,-1));
				}
			}
			$val = charliteral(implode(',',$val));
			//debugitem('sqlparameter '.$p,$val);
		}
		$r .= ",\n@$p=$val";
	}
	//debugitem('slqparameters1',$list);debugitem('slqparameters2',$r);
	return substr($r,1);
}

//
// FILL_ARRAY + UPDATE_ARRAY: naplní/updatuje hodnoty ze stringu, zadaného ve tvaru "A=cosi;B=Cosi jiného;C=další"
// Funkce se liší tím, že UPDATE_ARRAY nevytváří nové klíče, pouze updatuje existující na not-null hodnotu.
// Oddělovač je možno změnit předáním parametrů.
// Vhodná pro lokalizaci hodnot z jednoduchého stringu
//

function fill_array(&$aa,$s,$del2='=',$del1=';'){
	$pp=explode($del1,$s);
	debugitem('pp',$pp);
	foreach($pp as $p){
		if(count($vv=explode($del2,$p))<2) continue;
		$vv[0]=trim($vv[0]);
		$vv[1]=trim($vv[1]);
		$aa[$vv[0]]=$vv[1];
		debugitem('vv',$vv);
		debugitem('AA',$aa);
	}
};

function update_array(&$aa,$s,$del2='=',$del1=';'){
	$pp=explode($del1,$s);
	foreach($pp as $p){
		if(count($vv=explode($del2,$p,2))<2) continue;
		$vv[0]=trim($vv[0]);
		$vv[1]=trim($vv[1]);
		if(array_key_exists($vv[0],$aa) /* && $vv[1]*/){
			$aa[$vv[0]]=$vv[1];
		}
	}
};

function create_phrases($source,$pagename=null){
	global $phrases,$page;
	if(!$pagename) $pagename=$page;
	$phrases=helptext_to_array($source);
	$a=sqlfirstrow("select pc.name, convert(varchar(max),case when l.helptext not like '' then l.helptext else pc.helptext end) helptext
from dbsession s
	join php_page p on p.name='repo_menu_profile'
	join php_page_column pc on pc.php_page=p.php_page and pc.name='phrases'
	left outer join l_php_page_column l on l.php_page_column=pc.php_page_column and l.language=s.language
where s.spid=@@spid");
	if($a) update_array($phrases,$a['helptext']);
	array_replace_globals($phrases);
}
function helptext_to_array($s,$del2='=',$del1=';'){
	$aa=array();
	$pp=explode($del1,$s);
	foreach($pp as $p){
		if(count($vv=explode($del2,$p,2))<2) continue;
		$vv[0]=trim($vv[0]);
		$vv[1]=trim($vv[1]);
		$aa[$vv[0]]=$vv[1];
	}
	return $aa;
};

function reginput_array($n,$typ=2){
	reginput($n,$typ);
	$g=&$GLOBALS[$n];
	if(is_array($g)){
		if(in_array($typ,array(2,4,'int','bigint','bit','tinyint','smallint','uuid','guid')))
			return "'".implode(',',$g)."'";
	}
	return $g;
}

/*
	
	Funkce hidden_input generuje HTML syntaxi pro <input type=hidden ...>
	parametry mohou být předány v poli (jediný parametr jako $_POST) nebo zvlášť.
	Pokud je v prvním parametru předáno pole, pak se v druhém parametru předává parent-name.
*/

function hidden_input($name, $value='', &$append=''){
	if(is_array($name)){
		$r='';
		foreach($name as $n=>$v){
			if(is_array($v)){
				foreach($v as $vv) $r .= hidden_input($n.'[]',$vv);
			}
			else $r .= hidden_input($n,$v);
		}
		$append .= $r;
		return $r;
	}
	$name=htmlspecialchars($name);
	if(is_array($value)){
		foreach($value as $v)
			$append = hidden_input($name.'[]',$v,$append);
	} else {
		$value=htmlspecialchars($value);
		$append .= "<input type=hidden name=\"$name\" value=\"$value\">";
	}
	return $append;
}

function checkbox_input($name,$value,$checkvalue,$label='',$attr=''){
	$checked=($value==$checkvalue)?'checked':'';
	$input="<input type=checkbox name=\"$name\" value=\"".htmlspecialchars($value)."\" $checked $attr>";
	if($label) return "<label>$input$label</label>";
	return $input;
}

function html_checkbox($name,$checkvalue,$attr='',$value=1,$readonly=0){
	global $page_readonly;
	$checked=($value==$checkvalue)?'checked':'';
	$val=htmlliteral($value);
	$name=htmlliteral($name);
	$hidden=$checked?"<input type=hidden name=$name id=$name value=$val>":'';
	$input=($page_readonly || $readonly)?
		"<input type=checkbox value=$val $checked disabled>$hidden"
		:
		"<input type=checkbox id=$name name=$name value=$val $checked $attr>";
	return $input;
}

function write_log($s,$fileName="Ramses.log"){
	$fp = fopen((($sp=session_save_path())?$sp:$_SERVER['TEMP'])."/$fileName","a");
	fputs ($fp, date("\r\n===================\r\nY.m.d H:i:s")."\r\n$s");
	fclose($fp);
}

function implode_sql(&$a){
	if(is_array($a)) $a=charliteral(implode(',',$a));
	else $a="''";
}

// Funkce vytvořená Copilotem :-)

function validateDate($input, $time = true) {
	// Definice formátů pro kontrolu
	$formats = [
	'ODBC' => ['Y-m-d H:i', 'Y-m-d'], // ODBC formáty
	'local' => ['d.m.Y H:i', 'd.m.Y'], // Lokální formáty
	];

	if($input !== null) foreach ($formats as $type => $formatList) {
		foreach ($formatList as $format) {
			$dateTime = DateTime::createFromFormat($format, $input);
			// Kontrola, zda je datum platné a zda neobsahuje chyby
			if ($dateTime !== null AND $dateTime !== false ) {
				// Pokud je datum platné, vrátíme ho ve formátu ODBC
				if ($time) {
					// Vrátíme datum a čas
					return $dateTime->format('Y-m-d H:i');
				} else {
					// Vrátíme pouze datum
					return $dateTime->format('Y-m-d');
				}
			}
		}
	}

	// Pokud žádný formát neodpovídá, ale chceme vrátit čas, přidáme 00:00
	// if ($time) {
	// foreach ($formats['local'] as $format) {
	// $dateTime = DateTime::createFromFormat($format, $input);
	// if ($dateTime !== false && !array_sum($dateTime::getLastErrors())) {
	// // Vrátíme datum s časem nastaveným na 00:00
	// return $dateTime->format('Y-m-d') . ' 00:00';
	// }
	// }
	// }

	// Pokud žádný formát neodpovídá, vrátíme chybu
	return '';
}


// S přechodem na PHP 8 je funkce zcela předělána, protože prohlížeče už nyní podporují input type date nebo datetime-local

function HTML_Calendar($name,$input_value='',$mandatory=false,$time=false){
	global $page_readonly;
	$value=validateDate($input_value,$time);
	$m=$mandatory?'required':'';
	//$page_readonly=1;
	$width=$time?100:75;
	$spanwidth=($width+40)."px";
	$width .= "px";	if($page_readonly)
		return "<div style=display:table-cell;white-space:nowrap; class=\"yui-skin-sam\">
			<input type=text name=\"$name\" $m min=\"1900-01-01\" max=\"2120-01-01\" id=\"$name\" style=\"margin:0px;width:$width;padding:0px;background-color:gainsboro;\" value=\"$input_value\" readonly>
		</div>";

	$type=$time?'datetime-local':'date';
	$style=$value?"":"style='color:white;' onkeydown=\"this.style.color='black';\" oninput=\"this.style.color='black';\"";
	return "<input type=$type $m name=\"$name\" id=\"$name\" min=\"1900-01-01\" max=\"2120-01-01\" value=\"$value\" $style>";
}

/*
function HTML_Calendar($name,$value='',$mandatory=false,$time=false){
	global $page_readonly;
	$m=$mandatory?'true':'false';
	if($value===null) $value='';
	if(strtolower($value)=='null') $value='';
	if(substr($value,0,1)=="'" && substr($value,-1)=="'")
		$value=substr($value,1,-1);
	//debugitem("Cal1",$value);
	$value=date_from_string($value);
	//debugitem("Cal2",$value);
	if($value && $d=date_create($value)){
		$value=date_format($d,"d.m.Y");
		if($time) $value=date_format($d,"d.m.Y H:i");
	} else $value='';
	//debugitem('time',$time);
	$width=$time?100:75;
	$spanwidth=($width+40)."px";
	$width .= "px";
	$buttonStyle=htmlliteral("max-height:24px;height:24px;vertical-align:top;padding:0px 3px 2px 3px;margin:0px;");
	if($page_readonly)
		return "<div style=display:table-cell;white-space:nowrap; class=\"yui-skin-sam\">
			<input type=text name=\"$name\" id=\"$name\" style=\"margin:0px;padding:0px;width:$width;background-color:gainsboro;\" value=\"$value\" readonly>
		</div>";

	$checkFunction=$time?'check_datetime':'check_date';
	return "<div style=display:table-cell;white-space:nowrap; class=\"yui-skin-sam\"><input type=text name=\"$name\" id=\"$name\" style=\"width:$width\" value=\"$value\" onchange=\"return $checkFunction(this,$m);\" onfocus=\"$('#$name"."_calendar').css('visibility','hidden');\");>
	<button type=button style=$buttonStyle id=\"$name"."_button\" onclick=\"return open_calendar(this);\"><img src=\"images/calbtn.gif\" alt=Calendar></button></div>";
}
*/

function sqlresult_to_xml($q,$tag){
	global $datarow;
	//debugitem('D',$datarow);
	$r='';
	while(fetch_datarow($q)){
		$att='';
		foreach($datarow as $cn=>$val){
			if(is_numeric($cn)) continue;
			if($val || $val===0 || $val==='0'){
				$val=str_replace("\n",'\n',str_replace("\r",'\r',$val));
				$att .= " $cn=\"".htmlspecialchars($val).'"';
			}
		}
		$r .= "\r\n<$tag$att />";
	}
	next_result($q);
	return $r;
}

function xmloutput($r,$fn='',$package=''){
	global $charset;
	if(!$fn) $fn="Export.xml";
	if($package) $package=" package=".xmlliteral($package);
	header("Content-Type: text/xml; charset=$charset");
	header("Content-Disposition: attachment; filename=\"$fn\"");
	print "<?xml version=\"1.0\" encoding=\"$charset\"?".">
	<RamsesData$package>
	$r
	</RamsesData>";
}

/*
	
	Export právě nastaveného result-setu do CSV, exportují se hodnoty včetně hlavičky a konec
	19.10.2011 - nový parametr na vnucení jiných záhlaví
	
*/
function csv_export($q=null,$delimiter='',$headers=array(),$excludeColumns=''){
	global $datarow,$charset,$lang,$dbquery,$exportFileName,$result_wwwsession;
	// Je-li prvním parameterm string, pak byl vynechán a ostatní se posunou
	if(is_string($q))
		{$excludeColumns=$headers; $headers=$delimiter; $delimiter=$q; $q=null;}
	// Je-li prvním parametrem pole, pak byly první dva vynechány
	elseif(is_array($q)) {$excludeColumns=$delimiter; $headers=$q; $delimiter='';}
	if(is_string($excludeColumns)) $excludeColumns=explode(',',$excludeColumns);
	//debugitem('excludeColumns',$excludeColumns); debugprint(); die();
	if(!$q) $q=$dbquery;
	if(!$delimiter) {
		$delimiter=",";
		//if($lang=='cz') $delimiter=";";
		if(in_array($result_wwwsession['o_language'],array('cz','sk'))) $delimiter=";";
	}
	$r=''; $n=0;
	$fd=tmpfile();
	if($charset=='utf-8') fwrite($fd,"\xEF\xBB\xBF");
	$header=array();
	if(is_array($q)){
		foreach($q as $row){
			foreach($excludeColumns as $ec) unset($row[$ec]);
			if(!$n){
				foreach($row as $cn=>$val) $header[]=$cn;
				fputcsv($fd,$header,$delimiter,'"','');
			}
			fputcsv($fd,$row,$delimiter,'"','');
			$n++;
		}
	}
	else while(fetch_datarow($q)){
		$att='';
		$values=array();
		foreach($excludeColumns as $ec) unset($datarow[$ec]);
		foreach($datarow as $cn=>$val){
			if(is_numeric($cn)) continue;
			if(is_numeric($val)) $val=str_replace(".",",",$val);
			if(!$n) { // Na prvním řádku se exportuje záhlaví s názvy sloupců
				$header[] = array_item($headers,$cn,$cn);
			}
			// Replacnu tabulátor mezerou a zkrátím, jinak to excel zkurví
			if($delimiter==';' && strlen($val??'')>30000) $val=substr($val,0,30000);
			$values[] = $val;
		}
		if(!$n) fputcsv($fd,$header,$delimiter,'"','');
		fputcsv($fd,$values,$delimiter,'"','');
		$n++;
	}
	fseek($fd,0);
	$ef=sanitize_filename(($exportFileName?:"Export"));
	header("Content-Type: text/csv; charset=$charset");
	header("Content-Disposition: attachment; filename=\"$ef.csv\"");
	header("Cache-Control: public");
	while(!feof($fd)){
		print fread($fd,20000);
	}
	fclose($fd);
	//print fread($fd,200000000);
	//print fread($fd,20000000);
	die();
}

/*

	csv_into_array: funkce přežvýká obsah CSV souboru a výsledek uloží do pole. Vrací true/false podle úspěšnosti.
	V případě neúspěchu zanechá HTML string v globlní proměnné $errtext
	Parametry:
	- $fn = jméno souboru
	- $titles = seznam požadovaných názvů sloupců v záhlaví (v prvním řádku souboru), string s názvy oddělenýmmi čárkami
	- &$out = výstupní pole předané by odkazem
	- $dbnames = nepovinné pole, které konvertuje názvy v záhlaví na databázové názvy
*/
function csv_into_array($fn,$titles,&$out,$dbnames=''){
	global $errmsg,$lang,$csv_delimiter,$result_wwwsession;
	
	$delimiter=($csv_delimiter)?$csv_delimiter:((in_array($result_wwwsession['o_language'],array('cz','sk')))?";":',');
	$coltitles=is_array($titles)?array_values($titles):explode(',',$titles);
	$colnames=array();
	if(is_array($titles)){
		$keys=array_keys($titles);
		if(!is_numeric($keys[0])) $colnames=array_keys($titles);
	}
	if($dbnames || count($colnames)==0)
		$colnames=is_array($dbnames)?$dbnames:($dbnames?explode(',',$dbnames):$coltitles);
	$fd=is_resource($fn)?$fn:null;
	if($fd || ($fd=fopen($fn,'r'))){
		$cols=fgetcsv($fd,0,$delimiter,'"',"\xFF");
		//debugitem('coltitles',$coltitles);
		//debugitem('dbnames',$colnames);
		//debugitem('cols',$cols);
		//return;
		if(is_array($cols)){
			foreach($cols as &$c) $c=trim($c);
			$colindex=array();
			foreach($coltitles as $i=>$ct){
				if(($ci=array_search($ct,$cols))===false)
					$errmsg .= "<H3 style=color:red>Required column header '$ct' not found</H3>";
				else
					$colindex[$i]=$ci;
				}
		} else {
			print "<H3 style=color:red>Delimiter is not recognized</H3>";
			return false;
		}
		if(!$errmsg){
			while($a=fgetcsv($fd,0,$delimiter,'"',"\xFF")){
				$row=array();
				foreach($coltitles as $i=>$ct){
					$ci=$colindex[$i];
					$v=(array_key_exists($ci,$a))?$a[$ci]:"";
					$cn=$colnames[$i];
					$row[$cn]=$v;
				}
				$out[] = $row;
			}
		}
		fclose($fd);
		return $errmsg?false:true;
	}
	print "<H3 style=color:red>Unexpected error at opening file</H3>";
	return false;
}

function insert_request_message($msgtext,$charvalue){
	global $request_message_list;
	if(!is_array($request_message_list)) $request_message_list=array();
	$request_message_list[]=array('msgtext'=>$msgtext,'charvalue'=>$charvalue);
}

//
// request_messages: Funkce vrátí tabulku pro tisk zpráv ze serveru
//
function request_messages($q=null){
	global $datarow,$htmldatarow,$T_SERVER_MESSAGES,$T_ITEM,$T_VALUE,$max_request_message_severity,$requestMsgs
		,$request_message_list,$T_CAPTION,$T_DETAIL,$T_OBJECT,$rqm;
	$rqm=new request_message();
	$item_header=$T_SERVER_MESSAGES;
	$max_request_message_severity=-1;
	if(!is_resource($q) and !is_object($q)){
		if(is_string($q)) $item_header=$q;
		$q=sqlrun("execute select_request_message");
	}
	$r=$hObjtype=$hObjname=$hDetail='';
	$a=sqlarray_simple();
	$existsObjtype=$existsObjname=$existsDetail=0;
	foreach($a as $datarow) {
		if(!$existsObjtype and $datarow['obj_type']){
			$existsObjtype=1;
			$hObjtype="<th>$T_OBJECT";
		}
		if(!$existsObjname and $datarow['obj_name']){
			$existsObjname=1;
			$hObjname="<th>$T_CAPTION";
		}
		if(!$existsDetail and ($datarow['charvalue'] or $datarow['intvalue'])){
			$existsDetail=1;
			$hDetail="<th>$T_DETAIL";
		}
	}
	$default_colors=array('black','green','blue','red');
	foreach($a as $datarow){
		$htmldatarow=htmlspecbr($datarow);
		$indent=10*$datarow['indent']+2;
		$severity=$datarow['severity'];
		if($severity>$max_request_message_severity) $max_request_message_severity=$severity;
		
		$cv=$htmldatarow['charvalue'];
		if(array_key_exists($cv,$GLOBALS)) $cv=$GLOBALS[$cv];
		$v=(($c=$datarow['intvalue'])!=null)?"<td align=right>$c</td>":"<td>$cv</td>";
		$txt=replace_phrase(array_item($datarow,'msgtext'));
		$obj_type=replace_phrase(array_item($datarow,'obj_type'));
		$obj_type=$existsObjtype?"<td>$obj_type":"";
		$obj_name=$existsObjname?"<td>$htmldatarow[obj_name]":"";
		$color=array_item($datarow,'color')?:array_item($default_colors,$severity,'dimgray');
		if(!$existsDetail) $v='';
		$r .= "<tr style=\"color:$color;$datarow[style]\" ><td style=padding-left:$indent>$txt$obj_type$obj_name$v</tr>";
	} debugprint();
	if(is_array($request_message_list)) foreach($request_message_list as $rqm){
		$txt=$rqm['msgtext'];
		if(array_key_exists($txt,$GLOBALS)) $txt=$GLOBALS[$txt];
		$r .= "<tr><td>$txt<td>$rqm[charvalue]</tr>";
	}
	if($r){
		$requestMsgs="
		<table class='server_messages request_messages' cellpadding=3 border=1>
		<tr style=font-weight:bold><th>$item_header$hObjtype$hObjname$hDetail</tr>
		$r
		</table>";
		return $requestMsgs;
	}
}

function replace_phrase($txt){
	return array_item($GLOBALS,$txt,$txt);
}

// Funkce in_array_fix zkontroluje, zda je parametr v poli, jako "in_array"
// Pokud není, nastaví ho na hodnotu prvního prvku
// Druhý parametr může být seznam stringových konstant oddělených čáskami

function in_array_fix(&$s,$a){
	$pole=is_array($a)?$a:explode(',',$a);
	if(in_array($s,$pole)) return $s;
	foreach($pole as $item){ $s=$item; return $s;}
	return $s;
}
///////////////////////////////////////////////////////////////////////////////////////////
// Funkce ověří přítomnost aplikačních rolí zadaných seznamem kódů. Jedna stačí          //
// Vrací TRUE/FALSE, Implicitní parametr $abort způsobí print zprávy a ukončení requestu //
///////////////////////////////////////////////////////////////////////////////////////////
function check_user_access($codeList,$abort=true){
	global $result_wwwsession,$debugmode;
	$codes=explode(',',$codeList);
	foreach($codes as &$c) $c=charliteral($c);
	$code=implode(',',$codes);
	$a=sqlarray_simple("select 0 code,dbo.f_session_access(e.access_element) action, e.obj_type, e.obj_name, e.access_name from va_access_element e where e.access_element in($code) order by 2 desc");
	//$debugmode=1;debugitem('A',$a);debugprint();
	if(!$a) return false; //$result_wwwsession['right_orgadmin'];
	if($r=$a[0]['action']) return $r;
	if($abort){
		$roles=implode('<br />',$codes);
		print "<h2 style=color:red>Access denied !</h2>
		<h3>Required application role is not present at the moment:</h3>$roles";
		die();
	}
	return $r;
}

/*

	Funkce pro praci s poli

*/

// Funkce array_item získá hodnotu z pole, obsluhuje případ, kdy klíč není nalezen nebo předaný parametr není pole (například $_POST a $_$GET nemusí být předány)

function array_item($array,$key,$default=''){
	if(is_array($array) && array_key_exists($key,$array)) return $array[$key];
	return $default;
}

function &array_item_ref(&$array,$key,$default=''){
	if(is_array($array) && array_key_exists($key,$array)) return $array[$key];
	return $default;
}

function array_push_distinct(&$array,$val){
	if(is_array($val)) foreach($val as $v){
		if(in_array($v,$array,true)) continue;
		array_push($array,$v);
	} else {
		if(!in_array($val,$array,true)) array_push($array,$val);
	}
}

function array_unshift_distinct(&$array,$val){
	if(is_array($val)) foreach($val as $v){
		if(in_array($v,$array,true)) continue;
		array_unshift($array,$v);
	} else {
		if(!in_array($val,$array,true)) array_unshift($array,$val);
	}
}

function array_replace_ref(&$a,$b){foreach($b as $k=>$v)$a[$k]=$v;}
function array_replace_globals($b){foreach($b as $k=>$v)$GLOBALS[$k]=$v;}

function odbcDate($str){return $str?(substr($str,8,2).'.'.substr($str,5,2).'.'.substr($str,0,4)):'';}
function odbcDateTime($str){return $str?(substr($str,8,2).'.'.substr($str,5,2).'.'.substr($str,0,4).substr($str,10)):'';}

function hiddenInputsFromSQL($sql=null){
	global $datarow;
	$r='';
	if($sql) sqlrun($sql);
	while(fetch_datarow()){
		foreach($datarow as $cn=>$val){
			if(is_int($cn)) continue;
			$v=htmlliteral($val);
			$r .= "<input type=hidden name=returned_colnames[] value=$cn><input type=hidden name=returned_$cn value=$v>";
		}
		break;
	}
	if($sql){
		//debugitem('hiddenInputsFromSQL','free result');
		free_result();
	} else
		next_result();
	return $r;
}

// Funkce provede redirect na aktuální stránku, účelem je zabránit znovuodeslání formuláře metodou POST
// Predpoklada se, ze $STRIPPED_URI obsahuje aktualni URI
// 30.11.2024 - Pole $_POST nově 

function autoredirect($target=''){
	global $STRIPPED_URI;
	if(count($_POST) or $target){
		if(!$target) $target=$STRIPPED_URI;
		//print "HEADERS_SENT=".headers_sent();
		if(headers_sent())
			print "<script>document.location=".jsliteral($target).';</script>';
		else
			header("location",$target);
		die();
	}
}

// Skupina jednoduchých funkcí pro práci s proměnnou UNIQUEIDENTIFIER
// Vytvoření GUID bez {závorek}
function newid(){
	$s=md5(uniqid('Ramses',true).uniqid(gethostname(),true));
	return substr($s,0,8).'-'.substr($s,8,4).'-'.substr($s,12,4).'-'.substr($s,16,4).'-'.substr($s,20,12);
}
// Ověření, zda předaný parametr je platné GUID
function is_guid($guid){ /*if(!$guid) return false;*/ return (preg_match("/^(\{)?[a-f\d]{8}(-[a-f\d]{4}){4}[a-f\d]{8}(?(1)\})$/i", $guid));}




//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                              //
//    Funkce check_update_subpages() zkontroluje, zda bylo předáno pole update_subpages s právě jedním prvkem   //
//                                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

function check_update_subpages($guidReady=false){
	global $update_subpage, $update_subpages, $autosave, $button_save, $update_guid;
	$update_subpage='';
	sessioninput('autosave');
	reginput('button_save',4);
	
	if(!$guidReady){
		if(is_guid($g=array_item($_POST,'update_guid')))
			$update_guid="'$g'";
		else
			reginput('update_guid',2);
	}
	reginput('update_subpages');
	if(($autosave || $button_save) && is_array($update_subpages) && count($update_subpages)==1 && $update_guid && $update_guid!='NULL') $update_subpage=$update_subpages[0];
	//debugitem('return check_update_subpage',$update_subpage);
	return $update_subpage;
}


// Funkce vrátí HTML syntaxi pro zadávání položky "confirmed" formou radiobuttonů

function html_confirmed($value='',$name='confirmed',$attr=''){
	global $T_STATUS_DRAFT,$T_STATUS_CONFIRMATION,$T_STATUS_REJECTED,$T_STATUS_APPROVED,$datarow;
	if($value==='') $value=$datarow['confirmed'];
	$cc=array($T_STATUS_DRAFT,$T_STATUS_CONFIRMATION,$T_STATUS_REJECTED,$T_STATUS_APPROVED);
	$r='';
	foreach($cc as $c=>$t){
		$checked=($value==$c)?'checked':'';
		$r .= "<span><input type=radio name=\"$name\" value=\"$c\" $attr $checked><label for=\"$name\">$t</label></span>";
	}
	return $r;
}

function registerGlobalFromDatarow($colnames,$prefix=''){
	global $datarow;
	foreach(explode(',',$colnames) as $colname){
		$GLOBALS[$prefix.$colname]=$datarow[$colname];
	};
}

/*
	Funkce vrátí HTML syntaxi 3 radiobuttonů, které fungují jako filter na položku typu BIT
*/
function html_cbx_filter($name,$value){
	global $T_YES, $T_NO, $T_ALL;
	$r='';
	$a=array('1'=>$T_YES,'0'=>$T_NO,''=>$T_ALL);
	if(!array_key_exists($value,$a)) $value='';
	foreach($a as $v => $t){
		$checked=((string)$value===(string)$v)?'checked':'';
		$r .= "<input type=radio name=\"$name\" value=\"$v\" $checked>$t";
	}
	return $r;
}

/*
	Funkce otestuje, zda je k dispozici uživatelský modul zadaného jména
*/
function custom_module($name){
	global $result_wwwsession;
	if(strpos($result_wwwsession['php_modules'],"^$name^")===false) return false;
	return true;
}

function date_format4($d,$len=10){
	if(!$d) return '';
	return substr(date_format(new DateTime($d),'d.m.Y H:i'),0,$len);
}

function isValidURL($url)
{
	return preg_match('|^http(s)?://[a-z0-9-]+(.[a-z0-9-]+)*(:[0-9]+)?(/.*)?$|i', $url);
}

// Funkce pro konverzi textových položek v poli

function iconv_array($charset1,$charset2,$item){
	if(is_string($item)){
		return iconv($charset1,$charset2,$item);
	}
	if(is_array($item)){
		foreach($item as &$i) $i=iconv_array($charset1,$charset2,$i);
		return $item;
	}
	return $item;
}

// Function rebuilds query from actual $_GET array and $STRIPPED_URI
function rebuild_uri($params=null){ // Deprecated
	global $STRIPPED_URI;
	if($params===null) $params=&$_GET;
	$a=parse_url($STRIPPED_URI);
	$a['query']=http_build_query($params);
	return "$a[path]?".http_build_query($params);
}

// Function reload causes the will be loaded again with the same or modified GET parameters
function reload($params=null){
	global $STRIPPED_URI;
	if($params===null) $params=$_GET;
	$a=parse_url($STRIPPED_URI);
	$target="$a[path]?".http_build_query($params);
	if(headers_sent())
		print "<script>document.location=".jsliteral($target).';</script>';
	else
		header("location: $target");
	die();
}

// JSON_ENCODE a JSON_DECODE pro právě nastavený charset

function json_encodeCP($item){
	global $charset;
	return json_encode(iconv_array($charset,'utf-8',$item));
}

function json_decodeCP($item){
	global $charset;
	return iconv_array('utf-8',$charset,json_decode($item,true));
}

function getCurrentUrl() {
	// 1. Zjistíme protokol (řeší absenci REQUEST_SCHEME v IIS)
	$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || $_SERVER['SERVER_PORT'] == 443;
	$scheme = $isHttps ? "https" : "http";

	// 2. Sestavíme základní URL
	$pageURL = $scheme . "://" . $_SERVER["SERVER_NAME"];

	// 3. Přidáme port pouze pokud není standardní (80 pro HTTP, 443 pro HTTPS)
	$port = $_SERVER["SERVER_PORT"];
	if (($scheme === "http" && $port != "80") || ($scheme === "https" && $port != "443")) {
		$pageURL .= ":" . $port;
	}

	// 4. Přidáme zbytek cesty
	$pageURL .= $_SERVER["REQUEST_URI"];

	return parse_url($pageURL);
}

/*
	Funkce získá obsah buňky pro upload souboru. Parametry jsou
	- Jméno položky (zpravidla tabulky)
	- GUID položky
	- Název pro zobrazení
	- Zjištěná velikost
*/
function getFileUploadTd($itemType,$guid,$fileName,$fileLength,$spanId='fileInfo'){
	global $T_REMOVE;
	if(substr($guid,0,1)!="'") $guid="'$guid'";
	$buttonUpload=picturebutton("images/16x16_upload.png","upload_file('$itemType',$guid);","Upload","Upload file");
	$fileInfo=$fileLength?"$fileName ($fileLength)":"";
	$removeId="\"remove_$spanId\"";
	return "<td><span style=position:relative;top:0px;>$buttonUpload&nbsp;&nbsp; </span><span id=\"$spanId\" onclick=download_file('$itemType',$guid); style=text-decoration:underline;cursor:pointer;>$fileInfo</span> <input type=checkbox name=$removeId id=$removeId>$T_REMOVE</td>";
}

/*
	Funkce "jqteColumn" vrátí sloupeček z $datarow pro editaci pomocí jQuery-te.
	Vytvoří DIV s obsahem, když se na něj klikne, tak se promění na editovatelný objekt.
*/
function jqteColumn($columnName,$suffix=""){
	global $datarow,$page_readonly;
	$inputId=$columnName.($suffix?"_$suffix":"");
	$hiddenId="hidden_$inputId";
	if($page_readonly)
		return "$datarow[$columnName]";
	return "<div style=min-height:30px;background-color:#F8F8FF; onclick=\"showJqte(this,'$hiddenId','$inputId');\">$datarow[$columnName]</div>
		<div style=display:none id=\"$hiddenId\"><textarea class=edit name=\"$inputId\" id=\"$inputId\">$datarow[$columnName]</textarea></div>
	";
}

/*
	Funkce se používá k odstranění apostrofů z klíčové hodnoty, která může být předána s nimi nebo bez nich.
	Nejčastěji když jde o typ UUID nebo textový identifikátor.
	Pro funkci musí být splněna podmínka, že prvním a posledním znakem musí být apostrof.
	V takovém případě nahradí vnitřní zdvojené apostrofy jedním.
*/
function stripApostrophes(&$keyvalue){
	if(substr($keyvalue,0,1)==="'" and substr($keyvalue,-1)==="'"){
		$keyvalue=str_replace("''","'",substr($keyvalue,1,-1));
	}
}

function ramsesEncrypt($data, $key, $salt=''){
    return openssl_encrypt($data,'AES-256-CBC',$key,0,hex2bin(md5("RamsesSalt".$salt)));
}
function ramsesDecrypt($data, $key, $salt=''){
     return openssl_decrypt($data,'AES-256-CBC',$key,0,hex2bin(md5("RamsesSalt".$salt)));
}

function verticalText($s){
	$r='';
	foreach(str_split($s) as $item){
		$r .= "<div style=\"display:block;white-space:pre;transform: rotate(+90deg);\">$item</div>";
	}
	return "<div>$r</div>";
}

function array_to_utf8($input,$recurse=0){
	global $charset;
	if($recurse>10) return null;
	if(is_string($input)) return iconv($charset,'utf-8',$input);
	if(is_object($input)) $input=get_object_vars($input);
	if(is_array($input)) foreach($input as $key => &$val) $val=array_to_utf8($val,$recurse+1);
	return $input;
}

function array_from_utf8($input,$recurse=0){
	global $charset;
	if($recurse>10) return null;
	if(is_string($input)) return iconv('utf-8',$charset,$input);
	if(is_object($input)) $input=get_object_vars($input);
	if(is_array($input)) foreach($input as $key => &$val) $val=array_from_utf8($val,$recurse+1);
	return $input;
}

function array_total(&$from,&$to){
	foreach($from as $key=>$val){
		if(!is_numeric($val)) $val=0;
		$to[$key] = array_item($to,$key,0) + $val;
	}
}

function ob_end(){ $s=ob_get_contents(); ob_end_clean(); return $s;}

// Funkce "namelimit" upraví délku předaného stringu na max (default 40) znaků, případně doplní třemi tečkami

function namelimit(&$n,$namelist=null,$max=40){
	if(is_array($n)){
		$colnames=explode(',',$namelist);
		foreach($colnames as $colname) if(array_key_exists($colname,$n)) namelimit($n[$colname],$max);
		return;
	}
	$max=($namelist>0)?$namelist:40;
	if(strlen($n??'')>$max) $n=substr($n,0,$max-2)."..";
	return $n;
}

function generateUUID($trim=true){
   // Windows
     if (function_exists('com_create_guid') === true) {
         if ($trim === true)
             return trim(com_create_guid(), '{}');
         else
             return com_create_guid();
     }

     // OSX/Linux
     
     if (function_exists('openssl_random_pseudo_bytes') === true) {
         $data = openssl_random_pseudo_bytes(16);
         $data[6] = chr(ord($data[6]) & 0x0f | 0x40);    // set version to 0100
         $data[8] = chr(ord($data[8]) & 0x3f | 0x80);    // set bits 6-7 to 10
         return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
     }

     // Fallback (PHP 4.2+)
     mt_srand((double)microtime() * 10000);
     $charid = strtolower(md5(uniqid(rand(), true)));
     $hyphen = chr(45);                  // "-"
     $lbrace = $trim ? "" : chr(123);    // "{"
     $rbrace = $trim ? "" : chr(125);    // "}"
     $guidv4 = $lbrace.
               substr($charid,  0,  8).$hyphen.
               substr($charid,  8,  4).$hyphen.
               substr($charid, 12,  4).$hyphen.
               substr($charid, 16,  4).$hyphen.
               substr($charid, 20, 12).
               $rbrace;
     return $guidv4;
 }

function td2_removed($msg=''){
	global $datarow,$n,$pageitem_removed,$lang;
	$rs=($rem=array_item($datarow,'removed'))?
			"style=background-color:red;font-weight:bold;":"";
	if(!$rem) {
		if(!$msg){
			$msg="Confirm you really want to delete this record.";
			if(in_array($lang,array('cz','sk'))) $msg="Potvrďte, že chcete tuto položku zrušit.";
		}
		$msg=jsliteral($msg);
		$pageitem_removed->onclick="if(this.checked && !confirm($msg)) this.checked=false;";
	}
	return "<td $rs><input type=hidden name=removed_old value=$rem>$pageitem_removed->label".td1_input("removed");
}

function picturebutton_help($element="div_pb_help_target"){
	global $T_HELP;
	return picturebutton("images/16x16/Help.png","$('#$element').toggle();",$T_HELP,$T_HELP);
}

function global_phrase($t){
	if(array_key_exists($t,$GLOBALS)) $t=$GLOBALS[$t];
	return $t;	
}

function getCloseWindowImg($style=''){
	global $closeWindowImg,$no_menu,$no_title,$no_html,$ajaxpage,$debugmode;
	$closeWindowImg='';
	if($no_html OR $ajaxpage) return;
	if($no_menu){
		$ah=getallheaders();
		if(array_item($ah,'Sec-Fetch-Dest','document')!='iframe' and !getinput('iframe')){
			$onclick=htmlliteral("if(window.opener && !window.opener.closed) {window.close();window.opener.focus();return;}
			if(URL_CANCEL!='') document.location=URL_CANCEL; else document.location='index.php';");
			$closeWindowImg="<img src='images/16x16/Cancel.png' class=noprint style='cursor:pointer;margin:0px;position:fixed;top:0px;right:0px;$style' onclick=$onclick>";
		} //else debugitem('Headers',$ah);
	}
}

function getCloseWindowButton($style=''){
	global $closeWindowButton,$T_CLOSE;
	$synt="if(window.opener && !window.opener.closed) {window.close();return;} if(URL_CANCEL!='') document.location=URL_CANCEL; else document.location='index.php';";
	$closeWindowButton=picturebutton("images/16x16/Cancel.png",$synt,$T_CLOSE,$T_CLOSE);
}

function getHelpDiv($txt,$id='div_helptext_big'){ // Z předaného textu vytvoří obsah nápovědy
	global $T_HELP,$helpButton,$helpDiv,$helpCbx;
	$r=$helpButton=$helpDiv='';
	if(!$txt) return;
	$a=explode("\n",$txt);
	foreach($a as $t){
		$t=htmlawed($t);
		if(substr($t,0,2)=='--') $r .= "<tr><td><td>".substr($t,1);
		elseif(substr($t,0,1)=='-') $r .= "<tr><td>-<td>".substr($t,1);
		elseif(substr($t,0,1)=='*') $r .= "<tr><td colspan=2 style='height:10px;font-weight:bold;'>".substr($t,1);
		else $r .= "<tr><td colspan=2 style='height:10px;'>$t";
	}
	$helpButton=new PictureButton("images/16x16/Help.png","$('#$id').toggle(); window.onresize();",$T_HELP);
	$helpDiv=(new htmlElement("div"))
		->setId($id)
		->setClass("helptext_big")
		->setStyle("display:none;max-height:400px;overflow-y:auto;")
		->setText("<table><tr><td style='max-width:20px;'><img src='images/16x16/Help.png'><td style='width:99%;'>$T_HELP
	$r</table>");
	$helpCbx=(new htmlCheckbox())->setOnclick("$('#$id').toggle(); window.onresize();");
// 	$helpDiv="<div id=\"$id\" style='display:none;'>
// 	<table><tr><td style='max-width:20px;'><img src='images/16x16/Help.png'><td style='width:99%;'>$T_HELP
// 	$r</table></div>";
}

// Extended nl2br for excel
$brex='<br style="mso-data-placement:same-cell;">';
function nl2brex($s){
	global $brex;
	return str_replace('<br>',$brex??'',nl2br($s??'',false));
}

function requestDuration(){
	global $requestStartTime,$show_request_duration;
	if($show_request_duration){
		
		return number_format(round(microtime(true) - $requestStartTime,3),3). " sec";
	}
	else return "";
}


/*
function cleanup_odbc_result() {
    global $dbquery;
    if (!is_resource($dbquery) && !($dbquery instanceof ODBCResult)) {
        return;
    }

    do {
        $num_fields = @odbc_num_fields($dbquery);
				debugitem('num_fields',$num_fields);
        if ($num_fields > 0) {
            while (@odbc_fetch_row($dbquery)) {}
        }
    } while (@odbc_next_result($dbquery));

    @odbc_free_result($dbquery);
}
*/


/**
 * Uvolní aktuální SQL výsledek podle použitého databázového driveru (ODBC nebo SQLSRV).
 * 
 * Funkce používá globální proměnné $dbquery a $dbms. 
 * Pokud je $dbms jiná než 'odbc' nebo 'sqlsrv', vyvolá výjimku.
 */
function cleanup_result() {
    global $dbquery, $dbms;

    if ($dbms === 'odbc') {
        // Kontrola, jestli $dbquery je platný ODBC výsledek
        if (!is_resource($dbquery) && !($dbquery instanceof \ODBC\Result) && !($dbquery instanceof ODBCResult)) {
            return; // Není co čistit
        }

        // Pokud není ani jeden sloupec, není potřeba pokračovat
        if (@odbc_field_name($dbquery, 1) === false) return;

        // Projde všechny další sady výsledků, pokud existují (u procedur apod.)
        while (@odbc_next_result($dbquery)) {}

        // Pokusí se uvolnit výsledek
        if (!@odbc_free_result($dbquery)) {
            // Pokud se uvolnění nezdaří, zrušíme referenci
            $dbquery = null;
        }

    } elseif ($dbms === 'sqlsrv') {
        // Pro SQLSRV kontrolujeme, jestli $dbquery je objekt nebo resource (obojí může platit)
        if (is_resource($dbquery) || is_object($dbquery)) {
            @sqlsrv_cancel($dbquery); // Zruší aktuální dotaz
            $dbquery = null; // Zrušíme referenci
        }

    } else {
        // Pokud $dbms obsahuje neočekávanou hodnotu, vyvoláme výjimku
        throw new Exception("Unsupported database driver in cleanup_result(): " . var_export($dbms, true));
    }
}


/*
	fopen_bom - otevře soubor a nastaví $file_charset dle BOM, při zápisu ho zapíše dle $charset
*/
function fopen_bom(string $filename, string $mode) {
	global $charset, $file_charset;

	// Mapa známých BOM signatur pro různé charsety
	$bom_map = [
		'utf-8'		=> "\xEF\xBB\xBF",
		'utf-16le'	=> "\xFF\xFE",
		'utf-16be'	=> "\xFE\xFF",
		'utf-32le'	=> "\xFF\xFE\x00\x00",
		'utf-32be'	=> "\x00\x00\xFE\xFF",
	];

	// Pokud není $charset nastaveno, vezmeme výchozí z PHP
	if (!isset($charset) || !$charset) {
		$charset = strtolower(mb_internal_encoding());
	} else {
		$charset = strtolower($charset);
	}

	// Zjistíme, zda se bude číst nebo zapisovat
	$has_write = strpbrk($mode, 'wax');	// zápis, přidání nebo vytvoření
	$has_read  = strpbrk($mode, 'r+');	// čtení nebo update

	$fh = fopen($filename, $mode);
	if (!$fh) return false;

	// Zápis BOM při vytváření souboru (ne při append!)
	if ($has_write && isset($bom_map[$charset]) && strpos($mode, 'a') !== 0) {
		fwrite($fh, $bom_map[$charset]);
	}

	// Čtení BOM a detekce charsetu
	if ($has_read) {
		$max_len = max(array_map('strlen', $bom_map));
		$start = fread($fh, $max_len);
		rewind($fh);

		foreach ($bom_map as $enc => $bom) {
			if (strncmp($start, $bom, strlen($bom)) === 0) {
				fseek($fh, strlen($bom));	// přeskočit BOM
				$file_charset = $enc;
				break;
			}
		}
	}

	return $fh;
}

function fseek_bom($fd) {
	fseek($fd, 0);
	$peek = fread($fd, 4);

	if (substr($peek, 0, 3) === "\xEF\xBB\xBF") {
		// UTF-8 BOM (3 bajty) — čteme 4, vrátíme se o 1
		fseek($fd, 3);
	} elseif ($peek === "\xFF\xFE\x00\x00") {
		// UTF-32 LE — přesně 4 bajty, jsme už na správné pozici
		// není třeba další fseek
	} elseif ($peek === "\x00\x00\xFE\xFF") {
		// UTF-32 BE — totéž
	} elseif (substr($peek, 0, 2) === "\xFF\xFE") {
		// UTF-16 LE (2 bajty)
		fseek($fd, 2);
	} elseif (substr($peek, 0, 2) === "\xFE\xFF") {
		// UTF-16 BE (2 bajty)
		fseek($fd, 2);
	} else {
		// Žádný BOM — vrať se na začátek
		fseek($fd, 0);
	}
}

function my_strtolower($s) {
    global $charset;
    return $charset === 'utf-8'
        ? mb_strtolower($s, 'UTF-8')
        : iconv(
            'UTF-8', 
            'CP1250', 
            mb_strtolower(iconv('CP1250', 'UTF-8', $s), 'UTF-8')
        );
}

function sanitize_filename($filename) {
    // 1. Pokud je to Windows-1250, převedeme na UTF-8 pro bezpečnou práci
    // Detekce kódování není 100%, ale pro běžné české texty stačí:
    if (!preg_match('//u', $filename)) {
        $filename = iconv('CP1250', 'UTF-8//IGNORE', $filename);
    }

    // 2. Odstranění bílých znaků (trim)
    $filename = trim($filename);
    
    // 3. Odstranění kontrolních znaků (včetně \r, \n, \t)
    // Bez modifikátoru /u, aby to "nesežralo" speciální bajty, pokud by převod selhal
    $filename = preg_replace('/[\x00-\x1F\x7F]/', '', $filename);

    // 4. Odstranění problematických znaků pro souborové systémy
    $danger_chars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    $filename = str_replace($danger_chars, '_', $filename);

    // 5. Doporučení: Odstranění diakritiky (pro hlavičku Content-Disposition je to jistota)
    $filename = iconv('UTF-8', 'ASCII//TRANSLIT', $filename);
    
    // 6. Pro jistotu ještě jednou vyčistíme vše, co není písmeno, číslo, tečka nebo pomlčka
    $filename = preg_replace('/[^A-Za-z0-9\._\-]/', '_', $filename);

    return $filename;
}
/**
 * Získá kompletní řetězec IP adres klienta (všechny proxy skoky + koncový REMOTE_ADDR).
 * Slouží jako unikátní síťový otisk prstu (path) pro bezpečné párování relací.
 *
 * @return string Síťový řetězec uzlů (max 200 znaků).
 */
function get_client_ip_path(): string {
	$ips = [];

	// 1. Pokud existuje X-Forwarded-For, projdeme a sesbíráme celou proxy trasu
	if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
		$forwarded = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
		foreach ($forwarded as $ip) {
			$trimmed = trim($ip);
			if ($trimmed !== '') {
				$ips[] = $trimmed;
			}
		}
	}

	// 2. Přidáme i koncový fyzický uzel, který navázal spojení s webserverem
	if (!empty($_SERVER['REMOTE_ADDR'])) {
		$ips[] = trim($_SERVER['REMOTE_ADDR']);
	}

	// Fallback na localhost, pokud by byla pole prázdná
	if (empty($ips)) {
		return '127.0.0.1';
	}

	// 3. Odstraníme případné duplicity, spojíme čárkou a ořízneme na max 200 znaků pro MSSQL
	return substr(implode(', ', array_unique($ips)), 0, 200);
}