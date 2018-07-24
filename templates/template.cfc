# complex fenestration construction properties of each zone defined in ../zones/main.cfc
#SURFACE_COUNT
8 # surfaces
#CFC_INDEX CFC index for each surface (type of the CFC material, i.e. 0=no CFC, 1,2,..= CFC types)
0,0,0,0,0,0,1,2
#CFC_DATA
# layers in cfc type:  1 (exp. glazing, gap, blind)
# for Glazing: R-fr= front reflectance, R-bk= back reflectance, Tran= transmittance
# for Venetian Blind: R-fr= slat top reflectance, R-bk= slat bottom reflectance, Tran= slat transmittance
# For each layer: normal SOLAR optical properties - R_fr, R_bk, Tran.
# For each layer: normal VISIBLE optical properties - R_fr, R_bk, Tran. (CURRENTLY NOT USED)
# For each layer: normal LONGWAVE radiative properties - R_fr, R_bk, Tran.
#END_CFC_DATA
#GAS_SLAT_DATA 
# layer type index for cfc type:  1
# Gas mixture properties for each gap for cfc type:  1
#END_GAS_SLAT_DATA