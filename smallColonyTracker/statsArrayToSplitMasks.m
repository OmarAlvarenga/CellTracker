function out_masks = statsArrayToSplitMasks(stats,imsize)

minArea = 1000;
medfiltsize = 11;
maxeroderad = 50;
ntimes = length(stats);
ncellsperframe = cellfun(@(x)size(x,1),stats);
ncells = sum(cellfun(@length,stats));

%get all xyt data
xyt = zeros(ncells,3);
q = 1;
for ii = 1:ntimes
    xyt(q:(q+ncellsperframe(ii)-1),1:2) = cat(1,stats{ii}.Centroid);
    xyt(q:(q+ncellsperframe(ii)-1),3) = ii; %time number
    xyt(q:(q+ncellsperframe(ii)-1),4) =1:ncellsperframe(ii); %cell number within that frame
    xyt(q:(q+ncellsperframe(ii)-1),5) =cat(1,stats{ii}.Area); %areas
    q = q + ncellsperframe(ii);
end

%group into colonies
global userParam;
userParam.colonygrouping = 100;
allinds=NewColoniesAW(xyt(:,1:2));
xyti = [xyt,allinds];



ncolonies = max(allinds);
%
% figure; plot(xyt(:,1),xyt(:,2),'r.'); hold on;
% for ii = 1:ncolonies
%     coldata = xyti(allinds == ii,:);
%     mm  = mean(coldata,1);
%     text(mm(1),mm(2),int2str(ii),'Color','c');
% end

out_masks = false(imsize(1),imsize(2),ntimes);

for ii = 1:ncolonies %loop over colonies, find the ones that need to be split
    coldata = xyti(allinds == ii,:);
    nc_time =zeros(ntimes,1);
    nc_area = nc_time;
    for jj = 1:ntimes
        curr_inds = coldata(:,3) == jj;
        nc_time(jj) = sum(curr_inds); %number of cells in colony
        nc_area(jj) = sum(coldata(curr_inds,5)); %colony area
        if jj > 1 %store mask from last frame
            oldmask = tmpmask;
        end
        
        %make the mask of the current colony
        cellnums = coldata(curr_inds,4);
        tmpmask = false(imsize);
        tmpmask(cat(1,stats{jj}(cellnums).PixelIdxList))=true;
        
        if jj > 1
            if nc_time(jj) < nc_time(jj-1) && nc_area(jj) > 0.9*nc_area(jj-1) %lost a cell, didn't lose area
                intmask = tmpmask | oldmask;
                cc = bwconncomp(intmask);
                ncell = cc.NumObjects;
                if ncell == nc_time(jj-1)
                    outside = ~imdilate(tmpmask,strel('disk',1));
                    basin = imcomplement(bwdist(outside));
                    basin = imimposemin(basin, intmask | outside);
                    L = watershed(basin);
                    maskToUse = L > 1;
                    cc = bwconncomp(maskToUse);
                    a = regionprops(cc,'Area');
                    if min([a.Area]) > minArea %its good, move on.
                        disp(['Split: Colony ' int2str(ii) ' time ' int2str(jj) '. Used overlap with previous']);
                        out_masks(:,:,jj) = outmasks(:,:,jj) | maskToUse;
                        continue;
                    end
                end
                %if we are here, splitting needed, but overlap based
                %splitting failed. try erosion based. 
                numneeded = nc_time(jj-1);
                erode_rad = 1;
                while ncell < numneeded && erode_rad < maxeroderad
                    newmask = imerode(tmpmask,strel('disk',erode_rad));
                    cc = bwconncomp(newmask);
                    ncell = cc.NumObjects;
                    erode_rad = erode_rad + 1;
                end
                if erode_rad == maxeroderad
                    disp(['Warning: Failed to split. Colony ' int2str(ii) ' time ' int2str(jj)]);
                    maskToUse = tmpmask;
                    
                else
                    
                    outside = ~imdilate(tmpmask,strel('disk',1));
                    basin = imcomplement(bwdist(outside));
                    basin = imimposemin(basin, newmask | outside);
                    
                    L = watershed(basin);
                    testmask = L > 1;
                    cc = bwconncomp(testmask);
                    a = regionprops(cc,'Area');
                    if min([a.Area]) < minArea
                        disp(['Warning: discarding erode-based split. Resulting cells too small']);
                        maskToUse = tmpmask;
                    else
                        disp(['Split: Colony ' int2str(ii) ' time ' int2str(jj) '. Erode radius: ' int2str(erode_rad)]);
                        maskToUse = L > 1;
                    end
                end
            else %doesn't need splitting
                maskToUse = tmpmask;
            end
        else
            maskToUse = tmpmask; %first frame
        end
        out_masks(:,:,jj) = out_masks(:,:,jj) | maskToUse;
    end

end