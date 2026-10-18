<?php

/*
	Třída je sice určena pro jednu (první) zprávu, ale obsahuje kontejner na všechny zprávy v requestu.
	Instanci stačí vytvořit pouze pro první zprávu. Všechny další se přidají pomocí funkce "add_message"
*/

class request_message {
	// Změněno z historického "var" na moderní modifikátory viditelnosti "public"
	public $code;
	public $severity;
	public $tr_style;
	public $icon;
	public $msgtext;
	public $obj_type;
	public $obj_name;
	public $detail;
	public $rqm;
	public $include_header;
	
	// Statické vlastnosti
	public static $request_message_list = array();
	public static $max_severity = -1;
	
	public function __construct($msgtext = '', $severity = 0, $include_header = 0){
		$this->msgtext = $msgtext;
		$this->severity = $severity;
		$color = 'black';
		$this->detail = '';
		$this->include_header = $include_header;
		
		if($severity == 1) $color = 'green';
		if($severity == 2) $color = 'blue';
		if($severity > 2) $color = 'red';
		
		$this->tr_style = "color:$color;";
		
		if($msgtext){
			self::$request_message_list[] = $this;
			self::$max_severity = max(self::$max_severity, $severity);
		}
		$this->rqm = &self::$request_message_list;
	}
	
	// Odstraněn zastaralý ampersand (&) – objekty se vracejí referencí nativně
	public function add_message($msgtext, $severity = 0, $unshift = 0){
		$n = new request_message($msgtext, $severity);
		if($unshift) {
			array_unshift(self::$request_message_list, array_pop(self::$request_message_list));
		}
		return $n;
	}
	
	public function setobject($obj_type, $obj_name = ''){
		$this->obj_type = $obj_type;
		$this->obj_name = $obj_name;
		return $this;
	}
	
	public function setid($code){
		$this->code = $code;
		return $this;
	}
	
	public function setdetail($detail){
		$this->detail = $detail;
		return $this;
	}
	
	public function get_severity(){
		return self::$max_severity;
	}
	
	public function add_from_db(){
		$a = sqlarray_simple("execute select_request_message");
		// Přidána pojistka pro případ, že sqlarray_simple vrátí false/null
		if (is_array($a) || is_object($a)) {
			foreach($a as $m){
				$this->add_message($m['msgtext'], $m['severity'])
					->setobject($m['obj_type'], $m['obj_name'])
					->setdetail($m['charvalue'] . $m['intvalue']);
			}
		}
	}
	
	public function __toString(){
		global $T_SERVER_MESSAGES;
		$r = '';
		$any_code = $any_obj_type = $any_obj_name = $any_detail = 0;
		
		foreach(self::$request_message_list as $m){
			if($m->code) $any_code = 1;
			if($m->obj_type) $any_obj_type = 1;
			if($m->obj_name) $any_obj_name = 1;
			if($m->detail !== '') $any_detail = 1;
		}
		
		foreach(self::$request_message_list as $m){
			$r .= "<tr style='$m->tr_style;'>";
			if($any_code) $r .= "<td>" . htmlspecbr($m->code) . "</td>";
			$r .= "<td>" . htmlspecbr($m->msgtext) . "</td>";
			if($any_obj_type) $r .= "<td>" . htmlspecbr($m->obj_type) . "</td>";
			if($any_obj_name) $r .= "<td>" . htmlspecbr($m->obj_name) . "</td>";
			if($any_detail){
				if(is_numeric($val = htmlspecbr($m->detail)))
					$r .= "<td class='number'>" . htmlspecbr($m->detail) . "</td>";
				else
					$r .= "<td>$val</td>";
			}
			$r .= "</tr>"; // Opraveno chybějící uzavření řádku
		}
		
		$colspan = $any_code + $any_obj_type + $any_obj_name + $any_detail + 1;
		$header = $this->include_header ? "<tr class='header'><th colspan='$colspan'>$T_SERVER_MESSAGES</th></tr>" : "";
		
		if($r){
			$h = ($any_code ? "<th>ID</th>" : "") . "<th>Zpráva</th>" . ($any_obj_type ? "<th>Typ objektu</th>" : "") . ($any_obj_name ? "<th>Název objektu</th>" : "") . ($any_detail ? "<th>Detail</th>" : "");
			$r = "<table class='input_form request_messages'>$header\n\t\t\t<tr>$h</tr>\n\t\t\t$r\n\t\t\t</table>";
		}
		return $r;
	}
}