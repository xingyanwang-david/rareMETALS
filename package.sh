Rscript roxygenise.R
R CMD build rareMETALS;
R CMD INSTALL rareMETALS_6.6.tar.gz
git add .
git push original master
