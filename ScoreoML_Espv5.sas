
/***************************************************************************************************

Procedimiento para aplicar Naive-Bayes a los textos y poder clasificarlos.

***************************************************************************************************/

/*Paso 1: limpieza del campo que tiene el texto a categorizar.
lib: libreria donde se encuentra la tabla insumo.
d1: nombre de la tabla insumo debe de contener: texto y categoria.\
v1: nombre de la variable de texto a limpiar.*/
%macro p1_s(lib,d1,v1);
data tmp1(drop=descripcion1 descripcion2);
	set &lib..&d1.;
	descripcion1 = prxchange('s/\r\n+|\r+|\n+|\t+//',-1,&v1.);
	descripcion2 = COMPBL(TRANSLATE(upcase(trim(left(descripcion1))),'',"-'~ì®,;:.¥-`/_[]ó{}ø?+$&%*=()\!#Ö|∞°¢©±≥≠≠≠≠≠≠≠≠≠"));
	descripcion3 = COMPBL(TRANSLATE(upcase(trim(left(descripcion2))),'',"1234567890≠≠≠≠≠≠≠≠≠"));
	position=prxmatch(prxparse('/\w*\@\w?/'), descripcion3);
	usuario =  scan(substr(descripcion3,position),1); 
	dominio =  scan(substr(descripcion3,position),2); 
	position1=prxmatch(prxparse('/\@/'), usuario);
	usuario1 = substr(usuario,1,position1-1);
	&v1._clean = translate(descripcion3,'AEIOU','¡…Õ”⁄');
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
d1: nombre de la tabla insumo debe de contener: texto y categoria.\
v1: variable que contiene el texto a analizar.
v2: variable que contiene la clase.
*/
%macro p2_s(lib,d1,v1,lang);
proc tgparse data=&lib..&d1.
	ignore = work.EXCLUIR
	/*stemming = YES*/ LANG=&lang.
	key = P_key out = P_out 
	/*
	la tabla key te da las palabras y su rol.
	la tabla out te da el conteo por palabras.
	*/
	TAGGING = YES ; /*entities = YES;*/
	/*SYN = sashelp.engsynms;*/
	var &v1._clean;
	/*select  'PREP' 'PRON' 'DET' 'AUX' 'CONJ' 'INTERJ' 'ABBR' 'PUNCT' 'PREF' 'PART' 'NUM'  /  drop;*/
run;
data p_key_(keep=term key role);
	set p_key;
	if _ispar not in ('+') then output;
	where role not in ("Punct","");
run;
proc sql;
	create table tmp2 as
	select
		a._document_,
		a._count_,
		b.term,
		b.role
	from p_out as a left join p_key_ as b
	on (a._termnum_ = b.key)
	order by 1;
quit;
%mend;


/*Paso 3: la probabilidad de que aparezca la palabra i dado que esta en la clase j.
lib: libreria donde se encuentra la tabla insumo.
d1: nombre de la tabla insumo que se utiliza para correr el procedimiento.
Comunmente se utiliza la libreria work y la tabla que se genera con la macro p2_s, llamada: tmp2.
*/

%macro p3_s(lib,d1);
proc sql noprint;
select count(*) into: conteo from PROB_C;
create table tmp3 as
select a.*, b.prob_w_1, b.prob_w_1**a._count_ as pw1
from &lib..&d1. as a left join prob_w_1 as b on a.term = b.term and a.role = b.role
order by _document_;
quit;
%do i = 2 %to &conteo.;
proc sql;
create table tmp3 as
select a.*, b.prob_w_&i., b.prob_w_&i.**a._count_ as pw&i.
from tmp3 as a left join prob_w_&i. as b on a.term = b.term and a.role = b.role
where a.role not in ("Punct","")
order by _document_;
quit;
%end;
%mend;


/*Paso 4: Aplicacion de naive bayes para determinar la clase mas probable a la que pertenece el texto.
lib: libreria donde se encuentra la tabla insumo.
d1: nombre de la tabla insumo que se utiliza para correr el procedimiento.
Comunmente se utiliza la libreria work y la tabla que se genera con la macro p3_s, llamada: tmp3.
v1: variable que contiene el texto a analizar.
id: variable identificadora de la tabla insumo.
*/
	
%macro p4_s(lib,d1,v1,id);
Proc sql noprint;
select count(*) into: conteo from Prob_c;
create table tmp4 as
	select	_document_, exp( sum( log( pw1 ) ) ) as pro_1 
	from &lib..&d1.
	group by 1 	order by 1;
quit;
%do i=2 %to &conteo.;
Proc sql;
	create table tmp4_ as
	select _document_, exp( sum( log( pw&i. ) ) ) as pro_&i.		
	from &lib..&d1.
	group by 1 	order by 1;
	create table tmp4 as 
	select 	a.*, b.pro_&i.
	from tmp4 as a left join tmp4_ as b
	on a._document_=b._document_;
quit;
%end;

Proc sql noprint;
select p into: p_c1 from PROB_C (firstobs=1 obs=1); /*insumo 0*/
select clase into: c from PROB_C (firstobs=1 obs=1); /*insumo 0*/
create table tmp5 as
	select _document_,&p_c1.*pro_1 as p, "&c." as clase
	from tmp4
	order by 1;
quit;
%do i=2 %to &conteo.;
Proc sql noprint;
select p into: p_c from PROB_C (firstobs=&i. obs=&i.); /*insumo 0*/
select clase into: c from PROB_C (firstobs=&i. obs=&i.); /*insumo 0*/
create table tmp5_ as
	select _document_,&p_c.*pro_&i. as p, "&c." as clase
	from tmp4
	order by 1;
quit;
proc append base=tmp5 data=tmp5_ force; 
%end;
/*proc sql;
create table tmp5 as
select * from tmp5
order by 1, 2 desc;
quit;*/
proc sql;
create table tmp5_ as
select _document_, max(p) as p
from tmp5 
group by 1;
create table tmp5 as 
select a.*,b.clase from tmp5_ as a left join tmp5 as b
on a.p = b.p and a._document_ = b._document_
order by 1;
quit;
/*Decision de la clase*/
proc sql;
create table resultado as
select 	a.&id., a.&v1., b.clase from tmp1 as a left join tmp5 as b
on (a.index = b._document_)
order by a.index;
quit; 
%mend;


/*Paso 5: se hace el borrado de las tablas temporales.*/
%macro p5_s;
proc sql;
drop table P_KEY;
drop table P_KEY_;
drop table P_OUT;
drop table tmp1;
drop table tmp2;
drop table tmp3;
drop table tmp4;
drop table tmp4_;
drop table tmp5;
drop table tmp5_;
quit;
%mend;


/*
%p1_s(M,amazon_cells_labe_score,text);
%p2_s(work,tmp1,text);
%p3_s(work,tmp2);
%p4_s(work,tmp3);
%p5_s;
*/

%macro Score(lib,datos,texto,id,lang);
%p1_s(&lib.,&datos.,&texto.);/*Limpieza*/
%p2_s(work,tmp1,&texto.,&lang.);/*CategorizaciÛn de palabras*/
%p3_s(work,tmp2);/*Calculo de la probabilidad de que aparezca la palabra i dado que esta en la clase j.*/
%p4_s(work,tmp3,&texto.,&id.);/*Aplicacion Naive Bayes*/
/*%p5_s;*//*Borrado de tablas temporales*/
%mend;


/*Paso 6 (opcional): calculo de la asertividad.
lib: libreria donde se encuentra la tabla insumo.
insumo: nombre de la tabla insumo que se utiliza para correr el procedimiento.
resultado: nombre de la tabla que contiene el id del texto, la descripcion y la clase asignada.
Comunmente se utiliza la libreria work y la tabla que se genera con la macro p4_s, llamada: resultado.
id: variable identificadora de la tabla insumo.
*/
%macro Asertividad(lib,insumo,resultado,id,clase);
proc sql;
create table Ase as 
select a.*, b.&clase. as Clase_or 
from &resultado. as a left join &lib..&insumo. as b
on (a.&id. = b.&id.);
quit;
PROC FREQ DATA = ase
	ORDER=INTERNAL
;
	TABLES Clase_or * clase /
		NOCOL
		NOPERCENT
		NOCUM
		SCORES=TABLE
		ALPHA=0.05;
RUN; QUIT;
%mend;

/*Ejecucion Ejemplo de ejecucion*/
/*
%let lib = M;
%let datos = amazon_cells_labe_score;
%let texto = text;
%let clase = class;
%let resultado = resultado;
%let id = id;
%let lang = 'Spanish';


%Score(&lib.,&datos.,&texto.,&id.,&lang.);
%Asertividad(&lib.,&insumo.,&resultado.,&id.,&clase.);
*/
