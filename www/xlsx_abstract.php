<?php

// Tridy uvedene v tomto souboru zabezpecují pouze kontrolu pritomnosti tabulek a sloupcu

abstract class xlsx_abstract{
	var $reader, $mandatory_tables, $last_table
		,$package_code, $package_name, $import_name, $description, $version_date, $parameters, $prepared
		,$content
		,$rqm;

	final function __construct($reader,array $content_info){
		$this->rqm=new request_message();
		$this->content=$content_info;
		$this->package_code=$content_info['package_code'];
		$this->description=$content_info['description'];
		$this->version_date=$content_info['version_date'];
		$this->reader=$reader;
		$this->mandatory_tables=$parameters=array();
		$this->setDataType('package_code,description','varchar','CONTENT_INFO');
		$this->setDataType('version_date','date','CONTENT_INFO');
		//$this->m=new request_message();
		if(!$this->description) $this->rqm->add_message("Missing mandatory value in CONTENT_INFO",3)->setobject("Column","description"); 
		if(!$this->version_date) $this->rqm->add_message("Missing mandatory value in CONTENT_INFO",3)->setobject("Column","version_date");
		$this->reader->package_ready=($this->rqm->get_severity()>2)?0:1;
		$this->prepare();
		$this->import_name=($this->package_name?:"Import $this->package_code");
		if($this->rqm->get_severity()>2) {$this->rqm->add_message("Errors detected"); return;}
		$this->rqm->add_message("Import processes",1)
			->setobject("PHP CLASS",get_class($this),2);
	}
	
	abstract function prepare();
	
	function setDataType($columns,$type,$table='',$msgdetail=''){
		if(!$table) $table=$this->last_table;
		$this->reader->setDataType($columns,$type,$table,$msgdetail);
		$this->mandatory_tables[$table]=$this->last_table=$table;
		return $this;
	}
	
	function get_severity(){
		return $this->rqm->get_severity();
	}
	
	function run(){
		
	}
}

class xlsx_tag_attribute extends xlsx_abstract{
	function prepare(){
		$this->package_name="Import tagù a jejich hodnot";
		$this->setDataType('sort_code,builtin_code,caption_en,shortname_en,description_en,caption_cz,shortname_cz,description_cz','varchar','TAG_ATTRIBUTE')
			->setDataType('bcode_tag,sort_code,builtin_code,caption_en,mnemo,shortname_en,description_en,shortname_cz,caption_cz,description_cz','varchar','TAG_VALUE')
			;
		$m=new request_message();
		if($this->rqm->get_severity()>2) {$this->rqm->add_message("Errors detected"); return;}
	}
}
