# Datový model hierarchií a vazeb
## 1. Požadavky
### 1.1 Hierarchie
Každá entita (třída), která podporuje hierarchii, by měla splňovat tyto požadavky:
- řádky jsou uspořádany do jednoduché primární hierarchické struktury
  - každý řádek má své místo v hierarchii určené sort-kódem typu varchar
  - podřízené řádky mají kód delší, společná část se shoduje s kódem nadřízených
  - při editaci musí být ošetřena unikátnost kódu
- kromě toho mohou být vytvořeny další hierarchické struktury, poskytující jiné pohledy na tato data
  - musí být zavedena samostatná entita pro registraci dalších hierarchických struktur, navrhovaný fyzický název tabulky je "hierarchy"
  - každý řádek této entity popisuje jednu hierarchii
  - hierarchie může mít vazbu na jednu třídu, která sama hierarchická být nemusí, ale v pilotní verzi bude
    - tato vazba musí být promítnuta do tabulky "meta_link_def"
  - samotná tato tabulka je rovněž hierarchického typu, takže bude muset být v počátečním nastavení zavedena do systému s vazbou sama na sebe (na třídu "hierarchy")
  - pokud tato struktura nemá vazbu na třídu, pak se jedná o štítek (tag), kterým může být označen libovolný objekt v databázi, avšak i 
  - kromě názvu bude každá hierarchie obsahovat příznak, jestli jsou povoleny vazby i z vnitřních uzlů (not leaf)
  - další položky jsou k diskusi
- všechny uzly hierarchie budou v jedné tabulce, navrhovaný název "hierarchy_item" 
- hierarchie, která slouží k dědění vlastností nadřízených na  podřízené, by měla být uzamčena
  - uzamčení znamená, že je omezeno přepodřizování existujících řádků
  - omezení se týká uzlů, na nichž nebo na jejich podřízených už jsou platné vazby na jiné entity
- označování záznamů tagy slouží k filtrování záznamů tak, že filtru na vnitřní uzel vyhovují záznamy vázané na všechny podřízené
## 1.2 Vazby
Uživatel má mít možnost vytvářet si svoje vlastní vazby mezi libovolnými záznamy. V pilotní verzi postačí vazby pomocí tagů, které vyjadřují obecnou souvislost mezi záznamy.

## 2. Datový model

Entity (třídy), které podporují hierarchii, musí kromě standardních sloupců obsahovat tyto položky:
|Název|Typ|Popis
|-|-|-|
|sort_code|varchar(200)|Hierarchický kód, který slouží pro třídění a zároveň je v něm vyjádřena podřízenost položek. Podřízené položky mají kód delší.
|caption|varchar(200)|Název pro zobrazení v seznamu, který podléhá lokalizaci
|is_leaf|bit|Příznak, že položka nemá podřízené, že neexistuje delší kód. Tato položka by mohla být typu computed, ale musí být zadána explicitně, neboť chrání hierarchii proti nechtěným změnám.

Třída "hierarchy" obsahuje navíc položky:
|Název|Typ|Popis
|-|-|-|
|builtin_code|varchar(80)|Unikátní kód třídy|
|multiple|bit|Příznak, že cílový záznam může mít vazbu na víc položek hierarchie|
|leaf_only|bit|Příznak, že cílový záznam může mít vazbu jen na koncový uzel hierarchie|

Je otázkou, jestli hierarchie nemá být přímo promítnuta do tabulky meta_class a její builtin_code===class_name. Sloupce "multiple" a "leaf_only" pak účinkují v tabulce meta_link_def.

Třída "hierarchy_item" obsahuje navíc položku "hierarchy" odkazující na hierarchy.original

Všechny vazby mezi položkou hierarchie a cílovou třídou budou realizovány ve společné tabulce vazeb "link". Aby to fungovalo, musí být v tabulce "meta_link_def" přítomen příslušný záznam o propojení tříd.

## 3. Kandidáti na hierarchický model
Jedná se tabulky asset_class, threat, impact, scenario.
Ve všech těchto tabulkách budou koncové položky označeny sloupcem is_leaf=1.
Vnitřní uzly hierarchie představují pouhé složky, neznamená to však, že by na ně nesměly být vázány vlastnosti/vazby, které se dědí na podřízené uzly a koncové entity.

## 4. Hromadné přiřazení vlastností k hierarchii
Položils otázku, jestli bude zvolen model dynamického výpočtu vztahů pomocí funkce f_resolve_hierarchy, nebo budou zděděné vazby materializovány fyzickým zápisem do tabulky "link".

Materializace vazeb v tabulce "link" tím, že vazba na položku hierarchie se promítne do vytvoření skutečných vazeb u podřízených záznamů je dobrý nápad a jsem tomu nakloněn. Ve starém systému to u jedné agendy bylo realizováno a využívá to příznak dědění v tabulce "link", aby mohla být později zrušena, když dědění pomine. Složitější je však to, že vazba se může zdědit více cestami, třeba i s použitím víc než jedné hierarchie. Každý update vazby na kterékoli z hierarchii a jakákoli změna v jedné z hierarchií pak musí spustit úplný přepočet všech zděděných vazeb všech hierarchií. To může být docela složitý úkol s vlivem na performance.

Možným řešením, které zjednoduší přepočet, je realizovat to pomocí většího množství záznamů v tabulce "link". Nestačil by pouhý příznak is_derived, ale musely by tam být sloupce identifikující zdroj, odkud dědění pochází. Ty sloupce by musel být nejméně dva - třída a "original" - a oba by musely být navíc v seznamu sloupců, ze kterých se vypočítává identifikační sloupec "original". Druhou variantou je, jestli jsem neudělal nějakou logickou chybu, že by to mohl být jen jeden sloupec s název "ancestor_link", když považujeme za jisté, že předchůdcem je jiný link registrovaný v téže tabulce. Výsledným zjištěním, zda vazba je přítomna nebo ne, by pak musel být agregátní výraz.

Diskutujeme nyní o těchto variantách, síle a slabinách.

## 5. Otázka práce s šablonami organizací
Odpověď je poměrně jednoduchá, zvolen by měl být klonovací model, že hned při vytvoření organizace podle šablony se do ní zkopírují všechny objekty šablony. Později mohou být změny v šabloně propagovány do tenanta pouze explicitně zvláštním procesem, který může zahrnocat i schvalování.

<style>td{vertical-align:top;padding:0px 3px !important;}</style>















