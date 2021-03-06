#' Perform conditional analysis for single variant tests
#'
#' @param candidate.variant Candidate variant position;
#' @param score.stat.file files of score statistics
#' @param cov.file covariance matrix files
#' @param known.variant.vec range of candidate variant, expressed in a vector, e.g. c("1:12345","1:234567");
#' @param refaltList A list of ref, alt alleles, as well as variant frequencies, whether it needs to check AF as for flipping alleles;
#' @param test test of rare variant tests
#' @param maf.cutoff Cutoffs of MAF used for determining rare variants
#' @param alternative Alternative hypothesis to be tested
#' @param out.digits The number of digits used in the output
#' @param callrate.cutoff Cutoff of call rates. Sites with callrates lower than the cutoff will be labeled as missing
#' @param hwe.cutoff Cutoff of HWE p-values. Sites with HWE pvalues lower than the cutoff will be labeled as missing
#' @param knownCoding knownCoding option allows users to specify if a linear transformation needs to be applied known variants. Possible choices for knownCoding option include identical, burden, randomm-eff.
#' @return return a list of meta-analysis results
#' @export
conditional.rareMETALS.single.group <- function(candidate.variant,score.stat.file,cov.file,known.variant.vec,refaltList,maf.cutoff,alternative=c('two.sided','greater','less'),out.digits=4,callrate.cutoff=0,hwe.cutoff=0,correctFlip=TRUE,knownCoding="identity",impMissing=TRUE)
    {
        cat('Conditional analysis',candidate.variant[1],"\n",sep=" ");
        res <- conditional.rareMETALS.single.group.core(candidate.variant[1],score.stat.file,cov.file,known.variant.vec,refaltList,maf.cutoff,alternative,out.digits,callrate.cutoff,hwe.cutoff,correctFlip,knownCoding,impMissing);

        res.mat <- matrix(nrow=length(candidate.variant),ncol=ncol(res$res.out))
        res.mat[1,] <- res$res.out;
        res.formatted <- matrix(nrow=length(candidate.variant),ncol=ncol(res$res.formatted))
        res.formatted[1,] <- res$res.formatted;
        colnames(res.formatted) <- c("POS","REF","ALT","AF","PVALUE","N","BETA","SD","DIRECTION","COND");
        colnames(res.mat) <- c("CHROM","POS","REF","ALT","SAMPLE_SIZE","PVALUE","AF","BETA_EST","BETA_SD","DIRECTION","POS_REF_ALT_KNOWN","LOG","NOTE");
        res.list <- list();
        res.list[[1]] <- res$res;
        if(length(candidate.variant)>1)
            {
                for(ii in 2:length(candidate.variant))
                    {
                        cat('Conditional analysis',candidate.variant[ii],"\n",sep=" ");
                        res.ii <- conditional.rareMETALS.single.group.core(candidate.variant[ii],score.stat.file,cov.file,known.variant.vec,refaltList,maf.cutoff,alternative,out.digits,callrate.cutoff,hwe.cutoff,correctFlip,knownCoding,impMissing);
                        res.mat[ii,] <- res.ii$res.out;
                        res.formatted[ii,] <- res.ii$res.formatted;
                        res.list[[ii]] <- res.ii$res;
                        
                    }
            }
        return(list(res=res.list,
                    res.formatted=res.formatted,
                    res.out=res.mat))
    }

#' Perform conditional analysis for single variant tests
#'
#' @param candidate.variant Candidate variant position;
#' @param score.stat.file files of score statistics
#' @param cov.file covariance matrix files
#' @param known.variant.vec range of candidate variant, expressed in a vector, e.g. c("1:12345","1:234567");
#' @param refaltList A list of ref, alt alleles, as well as variant frequencies, whether it needs to check AF as for flipping alleles;
#' @param test test of rare variant tests
#' @param maf.cutoff Cutoffs of MAF used for determining rare variants
#' @param alternative Alternative hypothesis to be tested
#' @param out.digits The number of digits used in the output
#' @param callrate.cutoff Cutoff of call rates. Sites with callrates lower than the cutoff will be labeled as missing
#' @param hwe.cutoff Cutoff of HWE p-values. Sites with HWE pvalues lower than the cutoff will be labeled as missing
#' @param knownCoding knownCoding option allows users to specify if a linear transformation needs to be applied known variants. Possible choices for knownCoding option include identical, burden, randomm-eff.
#' @return return a list of meta-analysis results
#' @export
conditional.rareMETALS.single.group.core <- function(candidate.variant,score.stat.file,cov.file,known.variant.vec,refaltList,maf.cutoff,alternative=c('two.sided','greater','less'),out.digits=4,callrate.cutoff=0,hwe.cutoff=0,correctFlip=TRUE,knownCoding='identity',impMissing=TRUE)
    {
        alpha <- 0.05;maf.cutoff <- 1;no.boot <- 0;test <- "SINGLE";
        both.vec <- set.intersect(candidate.variant,known.variant.vec);
        gene.file <- "refFlat_hg19.txt.gz";        
        extra.pars <- list(alpha=alpha,out.digits=out.digits,QC.par=list(callrate.cutoff=callrate.cutoff,hwe.cutoff=hwe.cutoff));
        raw.data.all <- list();
        tabix.range <- get.tabix.range(c(candidate.variant,known.variant.vec));
        capture.output(raw.data.all[[1]] <- rvmeta.readDataByRange( score.stat.file, cov.file,tabix.range)[[1]]);
        tmp <- c("CHROM","POS","REF","ALT","SAMPLE_SIZE","PVALUE","AF","BETA_EST","BETA_SD","DIRECTION_BY_STUDY","POS_REF_ALT_ANNO_KNOWN","LOG","NOTE");
        res.single.out.0 <- matrix(NA,nrow=1,ncol=length(tmp));
        colnames(res.single.out.0) <- tmp;
        chrpos <- unlist(strsplit(candidate.variant,split=":"));
        res.single.out.0[1,1:2] <- chrpos;
        res.0 <- list(res.list=list(),res.out=res.single.out.0);
        if(length(raw.data.all)==0)
            {
                return(res.0)
                       
            }
 
        no.sample <- 0;
        res <- list(list(p.value=NA,statistic=NA,no.var=NA,no.sample=NA));
        p.value <- double(0);
        ref <- character(0);
        alt <- ref;
        direction.by.study <- character(0);
        ix.gold <- extra.pars$ix.gold;
        if(length(extra.pars$ix.gold)==0) {
            ix.gold <- 1;
        }
        out.digits <- extra.pars$out.digits;
        if(length(out.digits)==0) out.digits <- 4;
        statistic <- double(0);pos <- integer(0);anno <- character(0);direction <- integer(0);res.maf.vec <- double(0);beta1.est.vec <- double(0);beta1.sd.vec <- double(0);
        gene.name.out <- 0;p.value.out <- 0;statistic.out <- 0;no.site.out <- 0;beta1.est.out <- 0;beta1.sd.out <- 0;maf.cutoff.out <- 0;direction.burden.by.study.out <- 0;direction.meta.single.var.out <- 0;pos.ref.alt.out <- 0;pos.ref.alt.known.out <- 0;p.value.known.out <- 0;anno.known.out <- 0;
        pos.single.out <- candidate.variant;p.value.single.out <- NA;ref.single.out <- NA;alt.single.out <- NA;anno.single.out <- NA;maf.single.out <- NA;beta1.est.single.out <- NA;beta1.sd.single.out <- NA;pos.ref.alt.known.single.out <- NA;direction.single.out <- NA;p.value.known.single.out <- NA;anno.known.single.out <- NA;af.single.out <- NA;
        
        kk <- 1;    
        candidate.variant <- candidate.variant;
        raw.data <- raw.data.all[[1]];
        raw.data$pos <- gsub("_.*","",raw.data$pos);

        raw.data.ori <- raw.data;
        if(length(extra.pars$QC.par)>0) 
            raw.data <- QC(raw.data,extra.pars$QC.par,cov=1);
        log.mat <- raw.data$log.mat;
        candidate.variant <- set.intersect(candidate.variant,raw.data$pos);
        known.variant.vec <- set.intersect(known.variant.vec,raw.data$pos);
        ix.var <- 1:length(raw.data$ustat[[1]]);
        ix.match <- match(raw.data$pos,refaltList$pos);
        ref.gold <- refaltList$ref[ix.match];
        alt.gold <- refaltList$alt[ix.match];
        af.gold <- refaltList$af[ix.match];
        anno.gold <- refaltList$anno[ix.match];
        pos.gold <- refaltList$pos[ix.match];
        if(length(ix.match)==0) return(res.0);
        refaltList <- list(pos=pos.gold,
                           ref=ref.gold,
                           alt=alt.gold,
                           anno=anno.gold,
                           af.diff.max=refaltList$af.diff.max,
                           checkAF=refaltList$checkAF,
                           af=af.gold);
        ix.candidate <- match(candidate.variant,pos.gold);
        ix.known <- match(known.variant.vec,pos.gold);
        p.value.single.out <- NA;
        pos.single.out <- matrix(unlist(strsplit(pos.gold,split=":")),ncol=2,byrow=TRUE);
        direction.single.out <- NA;
        ref.single.out <- paste(ref.gold[ix.candidate],collapse=",");
        alt.single.out <- paste(alt.gold[ix.candidate],collapse=",");
        beta1.est.single.out <- NA;
        beta1.sd.single.out <- NA;
        maf.single.out <- NA;
        anno.single.out <- paste(anno.gold[ix.candidate],collapse=",");             
        p.value.known.single.out <- NA;
        anno.known.single.out <- paste(anno.gold[ix.known],sep=",",collapse=",");
        pos.ref.alt.known.single.out <- paste(pos.gold[ix.known],ref.gold[ix.known],alt.gold[ix.known],anno.gold[ix.known],sep="/",collapse=",");
 
        res.single.out <- res.single.out.0;
        ix.pop <- 1:length(raw.data$nSample);
        for(ii in 1:length(ix.pop))
        {   
            for(jj in 1:length(ix.var))
            {
                res.flipAllele <- flipAllele(raw.data,raw.data.ori,refaltList,ii,ix.var[jj],log.mat[ix.var[jj],],correctFlip);
                raw.data <- res.flipAllele$raw.data;
                log.mat[ix.var[jj],] <- res.flipAllele$log.mat.var;
                
            }
        }

        res.extra <- list(ref.candidate=refaltList$ref[ix.candidate],
                          alt.candidate=refaltList$alt[ix.candidate],
                          anno.candidate=refaltList$anno[ix.candidate],
                          pos.candidate=refaltList$pos[ix.candidate],
                          ref.known=refaltList$ref[ix.known],
                          tabix.range=tabix.range,
                          alt.known=refaltList$alt[ix.known],
                          anno.known=refaltList$anno[ix.known],
                          pos.known=refaltList$pos[ix.known],
                          raw.data=raw.data.ori,
                          clean.data=raw.data);
        
        res.null <- list(res.list=res.extra,
                         res.out=res.single.out);
        note <- "";
        
        if(length(both.vec)>0)
            {
                warning("Candidate variants overlaps with known variants");
                note <- "isKnownVariant";
            }
        
        if(length(candidate.variant)==0 | length(known.variant.vec)==0)
            {
                warning("No candidate variant or no known variants")
                note <- "noCandidate|noKnown";
                return(res.null);
            }
        if(length(candidate.variant)>0 & length(known.variant.vec)>0)
            {

                score.stat.vec.list <- list();mac.vec.list <- list();maf.vec.list <- list();cov.mat.list <- list();var.Y.list <- list();N.list <- list();mean.Y.list <- list();pos.list <- list();anno.list <- list();ac.vec.list <- list();af.vec.list <- list();
                af.mat <- matrix(NA,ncol=length(raw.data$ustat[[1]]),nrow=length(raw.data$ustat));
                ac.mat <- af.mat;
                N.mat <- af.mat;
                ref.list <- list();
                alt.list <- list();V.list <- list();


                U.stat <- 0;V.stat.sq <- 0;
                ustat.list <- list();
                vstat.list <- list();
                ix.X1 <- ix.candidate;
                ix.X2 <- ix.known;
                conditional.U.all <- 0;
                conditional.V.all <- 0;
                direction.single.vec <- 0;
                for(ii in 1:length(ix.pop)) {
                    N.list[[ii]] <- rm.na(as.integer(mean(raw.data$nSample[[ii]],na.rm=TRUE)));
                    N.mat[ii,] <- raw.data$nSample[[ii]];
                    no.sample <- no.sample+N.list[[ii]];
                    ustat.list[[ii]] <- raw.data$ustat[[ii]];
                    vstat.list[[ii]] <- raw.data$vstat[[ii]];
                    if(impMissing==FALSE) {
                        ustat.list[[ii]] <- rm.na(ustat.list[[ii]])
                        vstat.list[[ii]] <- rm.na(vstat.list[[ii]])
                    }
                    cov.mat.list[[ii]] <- matrix(raw.data$cov[[ii]][ix.var,ix.var],nrow=length(ix.var),ncol=length(ix.var));
                    V.list[[ii]] <- cov.mat.list[[ii]]*N.list[[ii]];
                    
                }
                impState <- NULL;

                
                for(ii in 1:length(ix.pop)) {                               
                    ustat.tmp <- ustat.list[[ii]];
                    if(knownCoding=="identity") {
                        res.tmp <- get.conditional.score.stat(ustat.tmp,V.list[[ii]],mean(N.mat[ii,],na.rm=TRUE),ix.candidate,ix.known,NULL)                        
                        conditional.U.ii <- as.numeric(res.tmp$conditional.ustat);
                        conditional.V.ii <- as.numeric(res.tmp$conditional.V)
                    }
                    if(knownCoding=="burden") {
                        ustat.tmp <- c(ustat.tmp[ix.candidate],sum(ustat.tmp[ix.known]))
                        V.ii <- rbind(cbind(matrix(V.list[[ii]][ix.candidate,ix.candidate],nrow=length(ix.candidate),ncol=length(ix.candidate)),
                                            matrix(rowSums(matrix(V.list[[ii]][ix.candidate,ix.known],nrow=length(ix.candidate),ncol=length(ix.known))),nrow=length(ix.candidate),ncol=1)),
                                            cbind(matrix(rowSums(matrix(V.list[[ii]][ix.candidate,ix.known],nrow=length(ix.candidate),ncol=length(ix.known))),ncol=length(ix.candidate),nrow=1),
                                                  matrix(sum(V.list[[ii]][ix.known,ix.known]),nrow=1,ncol=1)));
                            
                        res.tmp <- get.conditional.score.stat(ustat.tmp,V.ii,mean(N.mat[ii,],na.rm=T),ix.candidate,ix.known)
                        conditional.U.ii <- as.numeric(res.tmp$conditional.ustat);
                        conditional.V.ii <- as.numeric(res.tmp$conditional.V)
                        
                    }
                       
                    conditional.U.all <- conditional.U.all+rm.na(conditional.U.ii);
                    conditional.V.all <- conditional.V.all+rm.na(conditional.V.ii);
                    
                    if(is.na(conditional.U.ii)) direction.single.vec[ii] <- "X";
                    if(!is.na(conditional.U.ii))
                        {
                            if(conditional.U.ii>0) direction.single.vec[ii] <- "+";
                            if(conditional.U.ii==0) direction.single.vec[ii] <- "=";
                            if(conditional.U.ii<0) direction.single.vec[ii] <- "-";
                        }                        
                    
                    var.Y.list[[ii]] <- 1;
                    mean.Y.list[[ii]] <- 0;
                    af.vec.list[[ii]] <- (raw.data$af[[ii]]);
                    ac.vec.list[[ii]] <- (raw.data$ac[[ii]]);
                    af.mat[ii,] <- af.vec.list[[ii]][ix.var];
                    ac.mat[ii,] <- ac.vec.list[[ii]][ix.var];
                    pos.list[[ii]] <- (raw.data$pos)[ix.var];
                    ref.list[[ii]] <- refaltList$ref;
                    alt.list[[ii]] <- refaltList$alt;
                    anno.list[[ii]] <- refaltList$anno;
                }          
                
                if(impMissing==TRUE) {
                    res.impute <- imputeConditional(ustat.list,vstat.list,cov.mat.list,N.mat,NULL,ix.candidate,ix.known);
                    
                    conditional.U.all <- as.numeric(res.impute$conditional.ustat);
                    conditional.V.all <- as.numeric(res.impute$conditional.V);
                }
                statistic <- conditional.U.all/sqrt(conditional.V.all);                                
                if(alternative=="two.sided") {
                    statistic <- statistic^2;
                    if(!is.na(statistic)) {
                        if(statistic==Inf | statistic==-Inf) statistic <- NA;
                    }
                    p.value <- pchisq(statistic,df=1,lower.tail=FALSE);
                }
                
                beta1.est <- conditional.U.all/conditional.V.all;
                beta1.sd <- sqrt(1/conditional.V.all);
                maf.vec <- rep(0,length(af.vec.list[[1]]));
                af.vec <- maf.vec;            
                mac.vec <- 0;
                ac.vec <- 0;
                
                af.vec <- colSums(af.mat*N.mat,na.rm=TRUE)/colSums(N.mat,na.rm=TRUE);
                ac.vec <- colSums(ac.mat,na.rm=TRUE);
                N.vec <- colSums(N.mat,na.rm=TRUE);
                maf.vec <- af.vec;
                mac.vec <- ac.vec;
                res.extra$cov.mat.list <- cov.mat.list;
                res.extra$ustat.list <- ustat.list;
                res.extra$vstat.list <- vstat.list;
                res.extra$af.mat <- af.mat;
                res.extra$ac.mat <- ac.mat;
                res.extra$N.mat <- N.mat;
                res.extra$log.mat <- log.mat;
                res.extra$raw.data.ori <- res.extra$raw.data.ori;
                p.value.single.out <- format(p.value,digit=out.digits);
                pos.single.out <- paste(pos.gold[ix.candidate],sep='');
                direction.single.out <- paste(direction.single.vec,sep='',collapse='');
                ref.single.out <- c(ref.gold[ix.candidate]);
                alt.single.out <- c(alt.gold[ix.candidate]);
                beta1.est.single.out <- c(format(beta1.est,digits=out.digits));
                beta1.sd.single.out <- c(format(beta1.sd,digits=out.digits));
                af.single.out <- c(format(af.vec[ix.candidate],digits=out.digits));
                anno.single.out <- anno.gold[ix.candidate];
                log.out <- paste(log.mat[ix.candidate,],sep=",",collapse=",")
            }
        res.single.out <- cbind(matrix(unlist(strsplit(pos.single.out,split=":")),ncol=2,byrow=TRUE),ref.single.out,alt.single.out,N.vec[ix.candidate],p.value.single.out,af.single.out,beta1.est.single.out,beta1.sd.single.out,direction.single.out,pos.ref.alt.known.single.out,log.out,note);
        res.formatted <- cbind(pos.single.out,
                               ref.single.out,
                               alt.single.out,
                               myFormat(af.single.out,2),
                               myFormat(p.value.single.out,2),
                               N.vec[ix.candidate],
                               myFormat(beta1.est.single.out,2),
                               myFormat(beta1.sd.single.out,2),
                               direction.single.out,
                               pos.ref.alt.known.single.out);
        colnames(res.formatted) <- c("POS","REF","ALT","AF","PVALUE","N","BETA","SD","DIRECTION","COND");
        colnames(res.single.out) <- c("CHROM","POS","REF","ALT","SAMPLESIZE","PVALUE","AF","BETA_EST","BETA_SD","DIRECTION","POS_REF_ALT_KNOWN","LOG","NOTE");
        return(list(res=res.extra,
                    res.formatted=res.formatted,
                    res.out=res.single.out));        
    }
r2cov.mat <- function(r2.mat,maf.vec)
    {
        var.vec <- sqrt(maf.vec*(1-maf.vec)*2);
        var.mat <- (var.vec%*%t(var.vec));
        cov.mat <- r2.mat*var.mat;
        return(cov.mat);
    }
