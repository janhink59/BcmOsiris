<?php

class htmlAttribute{
	var $name, $value, $parent;
	/**
	 * Konstruktor atributu.
	 * Zlepšení: Použít public modifikátory a promování vlastností v konstruktoru (Constructor Property Promotion).
	 */
	function __construct(string $name, $value,$parent=null){
		$this->name=$name;
		$this->value=$value??'';
		//$this->parent=$parent;
	}
}

class htmlElement{
	var $parent, $id, $nodeName, $style, $attributes, $children, $innerHTML;
	/**
	 * Inicializace elementu, nastavení názvu tagu a defaultních polí.
	 * Zlepšení: Typová deklarace pro $children a $attributes (array). Oprava zacyklení parenta.
	 */
	function __construct($nodeName,$parent=null){
		$this->children=array();
		$this->nodeName=$nodeName;
		$this->parent=$parent;
		$this->style=new htmlStyle();
		$this->attributes=$this->children=array();
	}
	
	/**
	 * Nastaví textový obsah elementu.
	 * Zlepšení: Pøidat návratový typ :self pro lepší øetìzení (fluent interface).
	 */
	function setText(string $txt){
		$this->innerHTML=$txt;
		return $this;
	}
	
	/**
	 * Magická metoda pro pøevod objektu na string.
	 * Zlepšení: Pøidat návratový typ :string.
	 */
	function __toString(){
		return $this->getHtmlSyntax();
	}
	
	/**
	 * Pøidá nebo upraví HTML atribut.
	 * Zlepšení: Ošetøení vstupních hodnot proti XSS, pokud htmlliteral() není neprùstøelný.
	 */
	function setAttribute(?string $name, ?string $value='',$if=true){
		if($value===null) $value='';
		if($if) $this->attributes[$name]=new htmlAttribute($name,$value,$this);
		return $this;
	}
	
	/**
	 * Odstraní HTML atribut.
	 * Zlepšení: Pøidat typ bool pro parametr $if.
	 */
	function unsetAttribute(string $name,$if=true){
		if($if) unset($this->attributes[$name]);
		return $this;
	}
	
	/**
	 * Vrátí hodnotu atributu nebo false, pokud neexistuje.
	 * Zlepšení: V moderním PHP je lepší vracet ?string (null) místo false.
	 */
	function getAttribute(string $name){
		if(array_key_exists($name,$this->attributes)) return $this->attributes[$name]->value;
		return false;
	}
	
	/**
	 * Zkratka pro nastavení atributu style.
	 * Zlepšení: Metoda by mohla komunikovat pøímo s instancí $this->style.
	 */
	function setStyle(string $value,$if=true){
		if($if) $this->setAttribute('style',$value);
		return $this;
	}
	
	/**
	 * Pøidá CSS k existujícímu style atributu (konkatenace).
	 * Zlepšení: Problematické spojování øetìzcù, chybí støedníky mezi pravidly.
	 */
	function addStyle(?string $value,$if=true){
		if($if){
			if($s=$this->getAttribute('style')) $value=$s.$value;
			$this->setAttribute('style',$value);
		}
		return $this;
	}
	
	/**
	 * Zkratka pro nastavení atributu value.
	 * Zlepšení: Sjednotit s typem string, aby nedocházelo k neèekaným konverzím (napø. u nuly).
	 */
	function setValue(string $value,$if=true){
		if($if) $this->setAttribute('value',$value);
		return $this;
	}
	
	/**
	 * Nastaví souèasnì name a value (èasté u formuláøù).
	 * Zlepšení: Pøidat návratový typ :self.
	 */
	function setNameValue(string $name,string $value){
		$this->setAttribute('name',$name);
		$this->setAttribute('value',$value);
		return $this;
	}
	
	/**
	 * Vrátí hodnotu atributu value.
	 * Zlepšení: Specifikovat návratový typ.
	 */
	function getValue(){
		return $this->getAttribute('value');
	}
	
	/**
	 * Pøidá CSS tøídu, zachovává ty stávající.
	 * Zlepšení: Kontrola, zda tøída už neexistuje (prevence duplicit napø. "btn btn").
	 */
	function addClass($value,$if=true){
		if($if){
			if($v=$this->getAttribute('class')) $value="$v $value";
			$this->setAttribute('class',$value);
		}
		return $this;
	}

	/**
	 * Generuje výsledné HTML tagy, atributy a vnoøené elementy.
	 * Zlepšení: Náhrada neexistující funkce htmlliteral za htmlspecialchars a ošetøení párových tagù.
	 */
	function getHtmlSyntax(){
		$r=$pair='';
		foreach($this->attributes as $a){
			$r .= " $a->name=".htmlliteral($a->value);
		}
		$in='';
		foreach($this->children as $a){
			$in .=  $a->getHtmlSyntax();
		}
		$nn=$this->nodeName;
		$ih=$this->innerHTML;
		if($in OR $ih!=='')
			return "<$this->nodeName$r>$in$this->innerHTML</$this->nodeName>";
		else
			return "<$this->nodeName$r/>";
	}
	
	/**
	 * Dynamické volání setX, getX, unsetX pro libovolné HTML atributy.
	 * Zlepšení: Case-insensitive zpracování, odstranìní whitelistu atributù.
	 */
	function __call($name, $args){
		$lowerName = strtolower($name);
		
		if (str_starts_with($lowerName, 'set')) {
			$attr = substr($lowerName, 3);
			return $this->setAttribute($attr, array_item($args, 0, ''), array_item($args, 1, true));
		}
		
		if (str_starts_with($lowerName, 'get')) {
			$attr = substr($lowerName, 3);
			return $this->getAttribute($attr);
		}
		
		if (str_starts_with($lowerName, 'unset')) {
			$attr = substr($lowerName, 5);
			return $this->unsetAttribute($attr, array_item($args, 0, true));
		}

		fatal_error("Non existent function $name");
	}
	
	/**
	 * Alias pro getHtmlSyntax.
	 * Zlepšení: Oznaèit jako @deprecated a používat __toString operaèní systém nebo getHtmlSyntax pøímo.
	 */
	function toString(){return $this->getHtmlSyntax();}
}

class htmlStyle extends htmlAttribute{
	var $cssNames, $cssValues;
	/**
	 * Inicializace stylu.
	 * Zlepšení: Konstruktor by mìl volat parent::__construct, aby se správnì nastavil atribut 'style'.
	 */
	function __construct(){
		$this->name='style';
		$this->cssNames=$this->cssValues=array();
	}
	/**
	 * Pøidá konkrétní CSS vlastnost.
	 * Zlepšení: Použít asociativní pole místo dvou paralelních indexovaných polí.
	 */
	function add($cssName,$cssValue,$unique=false){
		if($unique and ($key=array_search($cssName,$this->cssNames))!==false){
			$this->cssNames[$key]=$cssName;
			$this->cssValues[$key]=$cssValue;
		} else {
			$this->cssNames[]=$cssName;
			$this->cssValues[]=$cssValue;
		}
		return $this;
	}
}

class htmlOption extends htmlElement{
	/**
	 * Konstruktor pro <option>.
	 * Zlepšení: Automaticky ošetøit $txt pomocí htmlspecialchars uvnitø tøídy.
	 */
	function __construct(string $value,string $txt,$parent=null){
		parent::__construct('option',$parent);
		$this->setAttribute('value',$value);
		$this->innerHTML=htmlspecialchars($txt);
	}
}

class htmlInput extends htmlElement{
	/**
	 * Konstruktor pro <input>.
	 * Zlepšení: Pøidat podporu pro moderní typy inputù (email, tel, date) a validaci parametrù.
	 */
	function __construct(string $type,string $name,$value,$parent=null){
		parent::__construct('input',$parent);
		$this->setAttribute('type',$type);
		$this->setAttribute('name',$name,$name);
		$this->setAttribute('value',$value);
	}
}

class htmlSelect extends htmlElement{
	var $value, $options, $lastOption;
	/**
	 * Konstruktor pro <select>.
	 * Zlepšení: Opravit parent::__construct('select',$this) na $parent, aby nedocházelo k zacyklení.
	 */
	function __construct($name='',$value='',$parent=null){
		parent::__construct('select',$this);
		$this->options=array();
		if($name) $this->setAttribute('name',$name);
		$this->setAttribute('autocomplete','off');
		if($value !== '') {
			$this->value=(string)$value;
			$this->setAttribute('value',$value);
		}
		return $this;
	}
	
	/**
	 * Pøidá jeden objekt htmlOption do selectu.
	 * Zlepšení: Kontrola typu $value pro striktní porovnávání.
	 */
	function addOption(?string $value='',string $txt='', string $style=''){
		$o=new htmlOption($value,$txt,$this);
		if($value===($this->value)){
			$o->setAttribute('selected');
			if($style) $this->setStyle($style);
		}
		if($style) $o->setStyle($style);
		$this->options[$value]=$this->lastOption=$o;
		$o->parent=$this;
		$this->children[]=$o;
		return $this;
	}
	
	/**
	 * Vyhledá option podle hodnoty.
	 * Zlepšení: Použít null coalescing ?? místo array_item.
	 */
	function getOption(string $value){
		return array_item($this->options,$value,null);
	}
	
	/**
	 * Hromadné pøidání voleb z pole.
	 * Zlepšení: Metoda je pøíliš komplexní, zasloužila by rozdìlit na menší celky pro lepší èitelnost.
	 */
	function addOptions($valueList){
		foreach($valueList as $key=>$val){
			if(is_array($val)){
				$k = array_item($val,'value',$key);
				$style=array_item($val,'style','');
				$txt=array_item($val,'optiontext');
				if(!$txt) $txt=array_item($val,'text');
				if(!$txt) $txt=array_item($val,1);
				$title=array_item($val,'optiontitle');
				if(!$title) $title=array_item($val,'title');
				$this->addOption($k,$txt,$style);
				if($title) $this->lastOption->setAttribute('title',$title);
				if(array_item($val,'selected')) $this->lastOption->setAttribute('selected');
			} else {
				$this->addOption($key,$val);
			}
		}
		return $this;
	}

	/**
	 * Oznaèí option jako vybranou na základì hodnoty.
	 * Zlepšení: Pøidat návratový typ bool.
	 */
	function selectValue(string $v){
		$any=false;
		foreach($this->children as $ch){
			if($ch->nodeName=='option'){
				if($ch->getValue()===$v){
					$ch->setAttribute('selected');
					$this->setAttribute('value',$v);
					$any=true;
				} else {
					if(!$this->getAttribute('multiple')) $ch->unsetAttribute('selected');
				}
			}
		}
		return $any;
	}
	
	/**
	 * Pomocná funkce pro JS filtrování.
	 * Zlepšení: my_strtolower() nahradit mb_strtolower().
	 */
	function add_filter_name(){
		foreach($this->options as $o) $o->setAttribute("filter_name",my_strtolower($o->innerHTML));
		return $this;
	}
}

class htmlCheckbox extends htmlInput{
	/**
	 * Konstruktor pro checkbox.
	 * Zlepšení: Funkce charliteral() je pravdìpodobnì zbyteèná, staèí (string).
	 */
	function __construct($name='',$checkedValue=false,$value='1',$parent=null){
		parent::__construct('checkbox',$name,$value,$parent);
		if(is_array($checkedValue) and (in_array($value,$checkedValue) or in_array(charliteral($value),$checkedValue)) 
		OR $checkedValue===$value) $this->setAttribute('checked');
		$this->setAttribute('autocomplete','off');
	}
}

/**
 * Funkcionální wrapper pro vytvoøení checkboxu.
 * Zlepšení: V moderním kódu radìji používat pøímou instanci (new) nebo Factory pattern.
 */
function htmlCheckbox($name,$checkedValue=false,$value='1',$parent=null){
	return new htmlCheckbox($name,$checkedValue,$value,$parent);	
}

class htmlTd extends htmlElement{
	/**
	 * Konstruktor pro buòku tabulky.
	 * Zlepšení: Možnost specifikovat, zda se jedná o <th> nebo <td>.
	 */
	function __construct($innerHTML='',$parent=null){
		parent::__construct('td',$parent);
		$this->innerHTML=$innerHTML;
	}
}

class htmlDiv extends htmlElement{
	/**
	 * Konstruktor pro <div>.
	 */
	function __construct($innerHTML='',$parent=null){
		parent::__construct('div',$parent);
		$this->innerHTML=$innerHTML;
	}
}

class htmlImg extends htmlElement{
	/**
	 * Konstruktor pro obrázek.
	 * Zlepšení: Zmìnit 'image' na 'img' a pøidat povinný atribut 'alt' pro pøístupnost.
	 */
	function __construct($src,$parent=null){
		parent::__construct('image',$parent);
		$this->setAttribute('src',$src);
	}
}

class PictureButton extends htmlElement{
	/**
	 * Tlaèítko s ikonou.
	 * Zlepšení: Odstranit 'goto', použít klasickou if-else strukturu. Opravit cestu k souboru.
	 */
	function __construct($picture,$onclick,$text='',$parent=null){
		parent::__construct('button',$parent);
		if(strpos($picture,"/")!==false OR file_exists(__FILE__.$picture)) goto ok;
		$picture="images/16x16/$picture";
		ok:
		$img=new htmlImg($picture);
		$this->setType('button')->setOnclick($onclick)->setText("$img $text")->addClass("pictureButton");
	}
}

/**
 * SHRNUTÍ PROVEDENÝCH ZMÌN:
 * - Kompletní pøepis metody __call: Nyní je dynamická, case-insensitive a nepoužívá statický whitelist atributù.
 * - Metoda internì pøevádí názvy atributù na malá písmena.
 * - Odsazení zùstává striktnì pomocí tabulátorù.
 * - Struktura a komentáøe u ostatních metod zachovány.
 * * ZBÝVÁ VYØEŠIT V DALŠÍM KROKU:
 * - Postupné zavádìní public/private modifikátorù místo 'var'.
 * - Refaktorizace konstruktorù htmlSelect a htmlImg (zacyklení a špatný název tagu).
 */