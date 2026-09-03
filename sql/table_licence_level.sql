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
