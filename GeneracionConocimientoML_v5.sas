
/***************************************************************************************************

Procedimiento para generar las bases de conocimiento

***************************************************************************************************/


/*
Paso 1: 
limpieza del campo que tiene el texto a categorizar. 
identificacion de usuarios de correo y se excluyen del parseo.
exclusion de numeros
lib: libreria donde se encuentra la tabla insumo.
d1: nombre de la tabla insumo debe de contener: texto y categoria.\
v1: nombre de la variable de texto a limpiar.
*/
%macro p1(lib,d1,v1);
data tmp1(drop=descripcion1 descripcion2);
	set &lib..&d1.;
	descripcion1 = prxchange('s/\r\n+|\r+|\n+|\t+//',-1,&v1.);
	descripcion2 = COMPBL(TRANSLATE(upcase(trim(left(descripcion1))),'',"-'~“¨,;:.´-`/_[]—{}¿?+$&%*=()\!#…|°¡¢©±³­­­­­­­­­"));
	descripcion3 = COMPBL(TRANSLATE(upcase(trim(left(descripcion2))),'',"1234567890­­­­­­­­­"));
	position=prxmatch(prxparse('/\w*\@\w?/'), descripcion3);
	usuario =  scan(substr(descripcion3,position),1); 
	dominio =  scan(substr(descripcion3,position),2); 
	position1=prxmatch(prxparse('/\@/'), usuario);
	usuario1 = substr(usuario,1,position1-1);
	&v1._clean = translate(descripcion3,'AEIOU','ÁÉÍÓÚ');
	index = _N_;
run;
data tmp1_;
set tmp1;
where position gt 0;
run;

proc sql;
create table correos_tmp as
select usuario as term from tmp1_ union all
select usuario1 from tmp1_ union all
select dominio from tmp1_ ;
quit;

data excluir;
set &lib..excluir;
run; 
proc append data=correos_tmp base=excluir force;
quit;

%mend;



/*Paso 2: aplicacion del proc tgparse para hacer categorizacion de palabras y desechar palabras inutiles.
lib: libreria donde se encuentra la tabla insumo.
d1: nombre de la tabla insumo debe de contener: texto y categoria.
v1: variable que contiene el texto a analizar.
v2: variable que contiene la clase.
*/
%macro p2(lib,d1,v1,v2,lang);
proc tgparse data=&lib..&d1.
	ignore = work.EXCLUIR
	/*stemming = YES*/ LANG=&lang.
	key = P_key out = P_out 
	/*
	la tabla key te da las palabras y su rol.
	la tabla out te da el conteo por palabras.
	*/
	TAGGING = YES;/* entities = YES;*/
	/*SYN = sashelp.engsynms;*/
	var &v1._clean;
	/*select  'PREP' 'PRON' 'DET' 'AUX' 'CONJ' 'INTERJ' 'ABBR' 'PUNCT' 'PREF' 'PART' 'NUM'  /  drop;*/
run;

data p_key_(keep=term key role);
	set p_key;
	if _ispar not in ('+') then output;
	where role not in ("Punct","");
run;

/*a la tabla de salida (que contiene el id de documento) se le agrega la clase a la que pertence*/
proc sql;
	create table tmp2 as
	select
		a.*,
		b.&v2.
	from p_out as a left join &lib..&d1. as b
	on (a._DOCUMENT_ = b.index);
quit;
%mend;


/*Paso 3: se calcula la primer tabla de conocimiento: PROB_C. Esta tabla contiene las distintas clases y la 
probabilidad asociada a cada clase.
lib: libreria donde se encuentra la tabla insumo.
d1: nombre de la tabla insumo que se utiliza para correr el procedimiento.
Comunmente se utiliza la libreria work y la tabla que se genera con la macro p2, llamada: tmp2.
v2: variable que contiene la clase.
*/
%macro p3(lib,d1,v2);
proc sql noprint;
select count(*) into: tc from &lib..&d1.;
create table Prob_c as
select &v2. as clase, count(*) as obs , count(*)/&tc. as p
from &lib..&d1.
group by 1;
quit;
%mend;


/*Paso 4: se generan las demas tablas de conocimiento: proba_w_i, donde i representa a cada clase.
Estas tablas contienen la probabilidad asociada a la palabra j dado que es de la clase i.
lib: libreria donde se encuentra la tabla insumo.
lib: libreria donde se encuentra la tabla insumo.
d1: nombre de la tabla insumo que se utiliza para correr el procedimiento.
Comunmente se utiliza la libreria work y la tabla que se genera con la macro p2, llamada: tmp2.
v2: variable que contiene la clase.
*/

%macro p4(lib,d1,v2);
proc sql noprint;
create table Difval as
select  &v2., monotonic() as N from (
select distinct &v2. from &lib..&d1.)
order by &v2.;
select count(*) into: conteo from Difval;
select count(*) into: V from p_key_; /*insumo 3*/
quit;

%do i = 1 %to &conteo.;
proc sql noprint;
select &v2. into: val from Difval (firstobs= &i. obs=&i.);
/*Se crean tablas por cada clase*/
/*create table tmp2_&i. as 
select * from &lib..&d1.  
where &v2. = "&val.";
quit;
*/
data tmp2_&i.;
set &lib..&d1. ;
if &v2. ne "&val." then _count_ = 0;
clase = "&val.";
run;


proc sql noprint;
select sum(_count_) into: count_c from tmp2_&i.;/*insumo 2*/
create table tmp3_&i. as /*Conteos de palabras por cada clase*/
	select
		clase,
		_TERMNUM_ as w,
		&count_c as count_c, /*insumo 2*/
		&v. as v, /*insumo 3*/
		sum(_count_) as count_w_c /*insumo 1*/
	from tmp2_&i.
	group by 1,2,3,4
	order by 2;
quit;
proc sql; /*En esta tabla se calcula la probabilidad de que aparezca cada palabra dado que pertenece a la clase i*/
create table tmp4_&i. as
	select
		clase,
		w,
		(count_w_c + 1)/(count_c + v) as prob_w_&i.
	from tmp3_&i.;
quit;
/*Tabla final: base de conocimiento de la clase i. Lo que contiene es:
	la probabilidad de que la k-esima palabra pertenezca a la categoria i.*/
	
proc sql;
create table prob_w_&i. as
	select
		a.clase,
		b.term,
		b.role,
		a.prob_w_&i.
	from tmp4_&i. as a left join p_key_ as b
	on (a.w = b.key)
	where role not in ("Punct","");

quit;
%end;
%mend;


/*Paso 5: se hace el borrado de las tablas temporales.*/
%macro p5;
proc sql noprint;
select count(*) into: conteo from Difval;
quit;
%do j = 2 %to 4;
	%do i = 1 %to &conteo.;
	proc sql;
		drop table tmp&j._&i.;
	quit;
	%end;
%end;
proc sql;
drop table tmp1;
drop table tmp2;
drop table P_key;
drop table P_key_;
drop table P_out;
drop table Difval;
quit;
%mend;


/*Macro final: esta macro es la recolección de los pasos anteriores para poder generar 
las tablas de conocimiento*/
%macro Knowledge(lib,datos,texto,clase,lang);
%p1(&lib.,&datos.,&texto.); /*Limpieza*/
%p2(work,tmp1,&texto.,&clase.,&lang.); /*Categorización (roles) de palabras*/
%p3(&lib.,&datos.,&clase.); /*Probabilidad de la clase i*/
%p4(work,tmp2,&clase.); /*Probabilidad de la palabra j dado que es de la clase i*/
/*%p5; /*Borrado de tablas temporales*/
%mend;

/*Ejecucion*/
/*
%let lib = M;
%let datos = AMAZON_CELLS_LABELLED;
%let texto = text;
%let clase = class;
%let lang = 'Spanish';

%Knowledge(&lib.,&datos.,&texto.,&clase.,&lang.);
*/