execute dropni 'licence_level'
GO
create table licence_level(
	licence_level tinyint not null primary key,
	name varchar(200) default '' not null,
	helptext varchar(max) default '' not null
)

/*
	Resets and fills the table licence_level
*/

delete from licence_level

-- Basic data

insert into licence_level values
	(0,'Demo',''),
	(10,'Standard',''),
	(20,'Expert',''),
	(30,'Custom',''),
	(40,'Enterprise',''),
	(255,'Developer','')
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'licence_level';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('licence_level','cs','T','licence_level','Úroveň licence','Úrovně licencí','Statický číselník licenčních úrovní systému (Demo, Standard, Expert, Custom, Enterprise, Developer).','Určuje rozsah dostupných funkcí a oprávnění licencované organizace.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('licence_level','en','Licence Level','Licence Levels','Static codetable of system licence levels (Demo, Standard, Expert, Custom, Enterprise, Developer).','Determines the scope of available features and permissions for a licensed organization.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'licence_level';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext) VALUES
	('licence_level','licence_level','cs','Úroveň licence (licence_level)','Úroveň licence organizace','Úroveň licence','Rozsah oprávnění organizace: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.'),
	('licence_level','licence_level','en','Licence Level (licence_level)','Organization Licence Level','Licence Level','Organization permission tier: 0 = Demo, 10 = Standard, 20 = Expert, 30 = Custom, 40 = Enterprise, 255 = Developer.');
END
GO