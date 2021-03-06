;+
; NAME:
;   escape_simulate_dimming
;
; PURPOSE:
;   Take observed dimming light curves from the Sun, make them look like they came realistically from other stars, then see how they'd look as measured by different instruments. 
;   Compare performance of the ESCAPE baseline, ESCAPE MidEx (scaled up), and EUVE
;
; INPUTS:
;   None
;
; OPTIONAL INPUTS:
;   distance_pc [float]:             How many parsecs distant is this star in units of parsecs? 
;                                    Default is 6 (CSR limit for solar type stars in DEEP survey). 
;   column_density [float]:          How much ISM attenuation to apply. 
;                                    Default 1d18 (a typical value for very near ISM)
;   coronal_temperature_k [float]:   The temperature of the corona of the star. If set to 1e6 (solar value) nothing is done. 
;                                    If >1e6, then a scaling is applied, shifting the amount of dimming from 1e6 K-sensitive lines toward this values emissions lines (if any). 
;                                    Default is 1e6 (solar value). 
;   expected_bg_event_ratio [float]: Flare intensity / background intensity on other stars can be vastly different than the sun. 
;                                    Dimming intensity / background intensity may also be. 
;                                    Be careful playing with this parameter. Have good justification for scaling it up or down, possibly based on MHD simulations.
;                                    Default is 1 (solar baseline). 
;   exposure_time_sec [float]:       How long to collect photons for a single exposure. The detector counts photons so in reality this can be done post facto rather than onboard.
;                                    Default is 1800 (30 minutes). 
;   num_lines_to_combine [integer]:  The number of emission lines to combine to boost signal. Will perform every combination of emission lines. Default is 5. 
;   
; KEYWORD PARAMETERS:
;   None
;
; OUTPUTS:
;   result [anonymous structure]: In order to have a single return, the multiple outputs are contained in this structure with the fields: 
;     time_sec [fltarr]: Elapsed time from arbitrary point before event.
;     snr [fltarr]: The signal to noise ratio over time for the event. 
;     depth [float]: The estimated dimming depth from simulated light curve. 
;     slope [float]: The estimated dimming slope from simulated light curve.
;     sigma_detection [float]: The confidence of the detection. 
;   
;   Plots to screen of the simulated light curve. 
;
; OPTIONAL OUTPUTS:
;   None
;
; RESTRICTIONS:
;   Requires access to the canonical SDO/EVE dimming curve and ESCAPE effective area files.
;   Must be run in the IDLDE due to the way the file with multiple sub-functions is written and then compiled. Else, need to put all the subfunctions in reverse order.
;   To run, make sure the IDLDE environment is clean by clicking the Reset Session button. Then click Compile button. Then click the Run button.
;
; EXAMPLE:
;   result = escape_simulate_dimming(distance_pc=25.2, column_density=18.03, coronal_temperature_k=1.9e6)
;-
PRO escape_simulate_dimming, distance_pc=distance_pc, column_density=column_density, coronal_temperature_k=coronal_temperature_k, expected_bg_event_ratio=expected_bg_event_ratio, exposure_time_sec=exposure_time_sec

  ; Defaults
  IF distance_pc EQ !NULL THEN distance_pc = 6.
  IF column_density EQ !NULL THEN column_density = 1d18
  IF coronal_temperature_k EQ !NULL THEN coronal_temperature_k = 1e6
  IF expected_bg_event_ratio EQ !NULL THEN expected_bg_event_ratio = 1.
  IF exposure_time_sec EQ !NULL THEN exposure_time_sec = 1800.
  IF num_lines_to_combine EQ !NULL THEN num_lines_to_combine = 5
  dataloc = '~/Dropbox/Research/Data/ESCAPE/'
  saveloc = '~/Dropbox/Research/ResearchScientist_APL/Analysis/ESCAPE Dimming Analysis/'
  
  ; Tuneable parameters
  escape_bandpass_min = 90 ; [??] shortest wavelength in the main ESCAPE bandpass
  escape_bandpass_max = 800 ; [??] longest ""  
  
  ; Read data
  eve = read_eve(dataloc, escape_bandpass_min, escape_bandpass_max)
  escape = read_escape(dataloc)
  escape_midex = read_escape_midex(dataloc)
  euve = read_euve(dataloc)
  
  ; Apply scalings to EVE data to make it look like observations of another star 
  eve_stellar = scale_eve(dataloc, eve, distance_pc, column_density, coronal_temperature_k, expected_bg_event_ratio)

  ; Fold stellar-simulated EVE data through effective areas (function adds intensity variable to the structure)
  escape = apply_effective_area(eve_stellar, escape)
  escape_midex = apply_effective_area(eve_stellar, escape_midex)
  euve = apply_effective_area(eve_stellar, euve)
  
  ; Account for exposure time
  escape = count_photons_for_exposure_time(escape, exposure_time_sec)
  escape_midex = count_photons_for_exposure_time(escape_midex, exposure_time_sec)
  euve = count_photons_for_exposure_time(euve, exposure_time_sec)
  
  ; Extract information relevant for dimming and assessment of instrument performance
  escape_dimming = characterize_dimming(escape, num_lines_to_combine)
  escape_midex_dimming = characterize_dimming(escape_midex, num_lines_to_combine)
  euve_dimming = characterize_dimming(euve, num_lines_to_combine)
  
  ; Compare the dimmings results
  p1 = plot(escape_dimming.time_sec, escape_dimming.snr, thick=2, $ 
            xtitle='time [sec]', $
            ytitle='signal/noise', $
            name='ESCAPE Baseline; $\sigma_{detect}$=' + escape_dimming.sigma_detection)
  p2 = plot(escape_midex_dimming.time_sec, escape_midex_dimming.snr, thick=2, 'dodger blue', /OVERPLOT, $
            name='ESCAPE MidEx; $\sigma_{detect}$=' + escape_midex_dimming.sigma_detection)
  p3 = plot(euve_dimming.time_sec, euve_dimming.snr, thick=2, 'tomato', /OVERPLOT, $
            name='EUVE; $\sigma_{detect}$=' + euve_dimming.sigma_detection)
  l = legend(target=[p1, p2, p3], position=[0.9, 0.9])
  
  STOP

END


FUNCTION read_eve, dataloc, escape_bandpass_min, escape_bandpass_max
  restore, dataloc + 'eve_for_escape/EVE Dimming Data for ESCAPE.sav'
  irradiance = eve.irradiance ; [W/m2/nm]
  wave = eve[0].wavelength * 10. ; [??] Converted from nm to ??
  jd = jpmtai2jd(eve.tai)
  time_iso = jpmjd2iso(jd)
  
  ; Truncate EVE wavelength to just the main ESCAPE band
  trunc_indices = where(wave GE escape_bandpass_min AND wave LE escape_bandpass_max)
  wave = wave[trunc_indices]
  irradiance = irradiance[trunc_indices, *] ; [W/m2/nm] = [J/s/m2/nm]
  
  ; Change irradiance units for consistency with ESCAPE
  J2erg = 1d7 
  m2cm = 100.
  nm2A = 10.
  A2cm = 1d8
  hc = 6.6261d-27 * 2.99792458d10
  irradiance = irradiance * j2erg / m2cm^2 / nm2A ; [erg/s/cm2/??]
  FOR i = 0, n_elements(irradiance[0, *]) - 1 DO BEGIN
    irradiance[*, i] /= (hc / (wave / A2cm)) ; [photons/s/cm2/??]
  ENDFOR
  
  ; TODO: Do I need to reduce the spectral resolution from 1 ?? (EVE) to 1.5 ?? (ESCAPE)
  ;    Actually the STM says ESCAPE projected performance is 0.92?? @ 171 ??. Is that what I should use? And is it very different at other wavelengths?
  
  return, {eve, wave:wave, irrad:irradiance, jd:jd, time_iso:time_iso}
END


FUNCTION read_escape, dataloc
  readcol, dataloc + 'effective_area/ESCAPE_vault_single460_effa_Zr_Zr.dat', $
    a_wave,a_aeff,grat40_aeff, grate20_aeff, a1_aeff40, a2_aeff40, a3_aeff40, a4_aeff40, a1_aeff20, a2_aeff20, $
    format='I, F, F, F, F, F, F, F, F', /SILENT
  return, {name:'ESCAPE CSR', wave:a_wave, aeff:a_aeff}
END


FUNCTION read_escape_midex, dataloc
  readcol, dataloc + 'effective_area/ESCAPE_effa_Pt_Zr040119.dat', $
    a_wave,a_aeff,grat40_aeff, grate20_aeff, a1_aeff40, a2_aeff40, a3_aeff40, a4_aeff40, a1_aeff20, a2_aeff20, $
    format='I, F, F, F, F, F, F, F, F', /SILENT
    
  ; Account for the data gap from 550-900 ?? in the file
  baseline = read_escape(dataloc)
  waves_to_add_indices = where(baseline.wave GE 550 and baseline.wave LT 900, count)
  IF count EQ 0 THEN BEGIN
    message, /INFO, 'No Aeffs found in baseline file to account for the gap in the MidEx file. There should be.'
    STOP
  ENDIF
  waves_to_add = baseline.wave(waves_to_add_indices)
  aeffs_to_add = baseline.aeff(waves_to_add_indices)
  ref_wave_for_scaling = 548 ; [??]
  scaling_factor = a_aeff[where(a_wave EQ ref_wave_for_scaling)] / baseline.aeff[where(baseline.wave EQ ref_wave_for_scaling)]
  aeffs_to_add *= scaling_factor[0]
  a_wave = [a_wave, waves_to_add]
  a_aeff = [a_aeff, aeffs_to_add]
  sort_indices = sort(a_wave)
  a_wave = a_wave[sort_indices]
  a_aeff = a_aeff[sort_indices]
    
  return, {name:'ESCAPE MidEx', wave:a_wave, aeff:a_aeff}
END


FUNCTION read_euve, dataloc
  readcol, dataloc + 'effective_area/EUVE_LW_Aeff_trim.txt', $
    a_wave_lw, a_aeff_lw, format='I, F', /SILENT
  readcol, dataloc + 'effective_area/EUVE_MW_Aeff_trim.txt', $
    a_wave_mw, a_aeff_mw, format='I, F', /SILENT
  readcol, dataloc + 'effective_area/EUVE_SW_Aeff_trim.txt', $
    a_wave_sw, a_aeff_sw, format='I, F', /SILENT

  ; Sum the three channels of EUVE since they were observed simultaneously
  FOR i = 0, max(a_wave_lw) DO BEGIN
    euve_wave = (n_elements(euve_wave) EQ 0) ? i : [euve_wave, i]
    aeff = 0
    index = where(a_wave_lw EQ i)
    IF index NE -1 THEN aeff += a_aeff_lw[index]
    index = where(a_wave_mw EQ i)
    IF index NE -1 THEN aeff += a_aeff_mw[index]
    index = where(a_wave_sw EQ i)
    IF index NE -1 THEN aeff += a_aeff_sw[index]

    euve_aeff = (n_elements(euve_aeff) EQ 0) ? aeff : [euve_aeff, aeff]
  ENDFOR
  wave = findgen(max(a_wave_lw) + 1)
  
  return, {name:'EUVE', wave:wave, aeff:euve_aeff}
END


FUNCTION scale_eve, dataloc, eve, distance_pc, column_density, coronal_temperature_k, expected_bg_event_ratio
  eve_stellar = scale_eve_for_distance(eve, distance_pc)
  eve_stellar = scale_eve_for_attenuation(dataloc, eve_stellar, column_density)
  eve_stellar = scale_eve_for_temperature(eve_stellar, coronal_temperature_k)
  eve_stellar = scale_eve_for_event_magnitude(eve_stellar, expected_bg_event_ratio)
  return, eve_stellar
END


FUNCTION scale_eve_for_distance, eve, distance_pc
  one_au = 1.5d13 ; [cm]
  one_pc = 3.09d18 ; [cm]
  eve.irrad = eve.irrad * (one_au / (distance_pc * one_pc))^2 ; [1/r^2]
  return, eve
END


FUNCTION scale_eve_for_attenuation, dataloc, eve_stellar, column_density
  doppler_shift = 0 ; [km/s]
  doppler_broadening = 10 ; [km/s]
  ism = h1he1abs_050(eve_stellar.wave, alog10(column_density), doppler_shift, doppler_broadening, xphi, lama, tall, $
                     dataloc_heI=dataloc+'atomic_data/', dataloc_h1=dataloc+'atomic_data/')
  transmittance = interpol(ism.transmittance, ism.wave, eve_stellar.wave)
  eve_stellar.irrad *= transmittance
  return, eve_stellar
END


FUNCTION scale_eve_for_temperature, eve_stellar, coronal_temperature_k
  ; TODO: implement this. For now, do nothing.
  return, eve_stellar
END


FUNCTION scale_eve_for_event_magnitude, eve_stellar, expected_bg_event_ratio
  ; TODO: implement this. For now, do nothing.
  return, eve_stellar
END


FUNCTION apply_effective_area, eve_stellar, instrument
  aeff = interpol(instrument.aeff, instrument.wave, eve_stellar.wave)

  intensity = eve_stellar.irrad
  FOR i = 0, n_elements(eve_stellar.irrad[0, *]) - 1 DO BEGIN
    intensity[*, i] = eve_stellar.irrad[*, i] * aeff ; [counts/s/??] ([photons/s/cm2/??] * [counts*cm2/photon]) - aeff also converts photons to counts
  ENDFOR
  instrument_updated = {name:instrument.name, wave:eve_stellar.wave, aeff:aeff, intensity:intensity, jd:eve_stellar.jd, time_iso:eve_stellar.time_iso}
  return, instrument_updated
END


FUNCTION count_photons_for_exposure_time, instrument, exposure_time_sec
  eve_time_binning = 10. ; [seconds] this is the cadence of the source EVE data, needed for rebinning
  t_sec = (instrument.jd - instrument.jd[0]) * 86400.
  number_of_exposures = ceil(max(t_sec)/exposure_time_sec)
  intensity_exposures = dblarr(n_elements(instrument.aeff), number_of_exposures)
  jd_centers = dblarr(number_of_exposures)
  time_iso_centers = strarr(number_of_exposures)
  
  t_step = 0
  i = 0
  WHILE t_step LT max(t_sec) DO BEGIN
    exposure_interval_indices = where(t_sec GE t_step AND t_sec LT (t_step + exposure_time_sec))
    IF exposure_interval_indices EQ [-1] THEN message, /INFO, 'Uh oh. No times found in exposure interval.'
    intensity_exposures[*, i] = (total(instrument.intensity[*, exposure_interval_indices], 2)) * eve_time_binning

    ; new center time
    jd_centers[i] = instrument.jd[exposure_interval_indices[n_elements(exposure_interval_indices)/2]]
    time_iso_centers[i] = instrument.time_iso[exposure_interval_indices[n_elements(exposure_interval_indices)/2]]
    
    t_step+=exposure_time_sec
    i++
  ENDWHILE

  instrument_updated = {name:instrument.name, wave:instrument.wave, aeff:instrument.aeff, intensity:intensity_exposures, jd:jd_centers, time_iso:time_iso_centers, exposure_time_sec:exposure_time_sec}
  return, instrument_updated
END


FUNCTION characterize_dimming, instrument, num_lines_to_combine
  emission_lines = extract_emission_lines(instrument)
  preflare_baselines_single_lines = estimate_preflare_baseline(emission_lines)
  depths_single_lines = get_dimming_depth(emission_lines, preflare_baselines_single_lines.intensity)
  depths_combo_lines = combine_lines(emission_lines, num_lines_to_combine)
  
  p1 = plot_dimming_performance(depths_single_lines, instrument, 1)
  p_multi = plot_dimming_performance(depths_combo_lines, instrument, num_lines_to_combine)

  STOP
  

  
  
  ; Example plot of light curve
  wave_171_174_indices = where((instrument.wave GE 170.1 AND instrument.wave LE 172.1) OR (instrument.wave GE 174.3 AND instrument.wave LE 176.3))
  intensity_171_174 = total(instrument.intensity[wave_171_174_indices, *], 1, /NAN) * 0.2 ; [counts] -- 0.2 is the EVE wavelength bin width

  ; Errors assume simple Poisson counting statistics (only valid if counts > ~10)
  w = window(location=[2735, 0], dimensions=[650, 400])
  p1 = errorplot(emission_lines.jd, intensity_171_174[0:-2], sqrt(intensity_171_174[0:-2]), thick=2, xtickunits='time', /CURRENT, $
                 title=instrument.name + '; exposure time = ' + jpmprintnumber(instrument.exposure_time_sec, /NO_DECIMALS) + ' seconds', $
                 xtitle='hours', $
                 ytitle='intensity [counts]')
                 
  STOP
  
  
  
  
;  ; Errors assume simple Poisson counting statistics (only valid if counts > ~10)
;  p1 = errorplot(emission_lines.jd, reform(emission_lines.intensity[15, *]), sqrt(reform(emission_lines.intensity[15, *])), thick=2, xtickunits='time', $
;                 title=instrument.name + '; exposure time = ' + jpmprintnumber(instrument.exposure_time_sec, /NO_DECIMALS) + ' seconds', $
;                 xtitle='hours', $
;                 ytitle='intensity [counts]')
;  p2 = plot(p1.xrange, [preflare_baselines[15], preflare_baselines[15]], linestyle='dashed', 'tomato', /OVERPLOT)
;  
;  STOP ; TODO: This is a temporary plot that needs to be checked -- really what I want to see?
  
  dimming = -1
  return, dimming
END


FUNCTION extract_emission_lines, instrument
;  line_centers = [93.9, 101.6, 103.9, 108.4, 117.2, 118.7, 121.8, 128.8, 132.8, 132.9, 135.8, 148.4, 167.5, 168.2, 168.5, 171.1, 174.5, $
;                 175.3, 177.2, 179.8, 180.4, 182.2, 184.5, 184.8, 185.2, 186.6, 186.9, 186.9, 188.2, 188.3, 192.0, 192.4, 193.5, 195.1, $
;                 196.5, 202.0, 203.8, 203.8, 211.3, 217.1, 219.1, 221.8, 244.9, 252.0, 255.1, 256.7, 258.4, 263.0, 264.8, 270.5, 274.2, $
;                 284.2, 292.0, 303.3, 303.8, 315.0, 319.8, 335.4, 353.8, 356.0, 360.8, 368.1, 417.7, 436.7, 445.7, 465.2, 499.4, 520.7] ; Comprehensive list
  line_centers = [171.1,177.2, 180.4, 195.1, 202.0, 211.3, 368.1, 445.7, 465.2, 499.4, 520.7] ; Selected list of those expected to be dimming sensitive
  intensity = dblarr(n_elements(line_centers), n_elements(instrument.intensity[0, *]))
  wave_bin_width = instrument.wave[1] - instrument.wave[0]
  FOR i = 0, n_elements(line_centers) - 1 DO BEGIN
    wave_indices = where(instrument.wave GE line_centers[i]-1 and instrument.wave LE line_centers[i]+1, count)
    IF count EQ 0 THEN BEGIN
      message, /INFO, 'Did not find any wavelengths around the emission line center, but should have.'
      STOP
    ENDIF
    intensity[i, *] = total(instrument.intensity[wave_indices, *], 1, /NAN) * wave_bin_width ; [counts]
  ENDFOR
  
  ; Drop final point in time which is always invalid for some reason 
  jd = instrument.jd[0:-2]
  time_iso = instrument.time_iso[0:-2]
  intensity = intensity[*, 0:-2]
  
  return, {emission_lines, wave:line_centers, intensity:intensity, jd:jd, time_iso:time_iso} 
END


FUNCTION estimate_preflare_baseline, emission_lines
  preflare_baselines = dblarr(n_elements(emission_lines.wave))
  uncertainty = preflare_baselines
  FOR i = 0, n_elements(emission_lines.intensity[*, 0]) - 1 DO BEGIN
    line = emission_lines.intensity[i, *] 
    preflare_baselines[i] = median(line) ; The simplest possible estimate -- inspected all by eye and they are all reasonable
    sigmas = cgpercentiles(line, percentiles=[0.159, 0.5, 0.841])
    uncertainty[i] = mean([sigmas[2] - sigmas[1], sigmas[1] - sigmas[0]])
  ENDFOR
  return, {intensity:preflare_baselines, uncertainty:uncertainty}
END


FUNCTION get_dimming_depth, emission_lines, preflare_baselines
  minimum = min(emission_lines.intensity[*, 0:11], dimension=2) ; The 0:11 is because dimming in this example occurred mainly before 2011-02-15T06:15:03Z, which is the 12th index into the array
  uncertainty = sqrt(minimum) ; [counts]
  depth = (preflare_baselines - minimum) / preflare_baselines * 100. ; [% from baseline]
  depth_over_squared_baseline = minimum/(preflare_baselines^2.)
  return, {depth:depth, depth_over_squared_baseline:depth_over_squared_baseline, uncertainty:uncertainty}
END


FUNCTION combine_lines, emission_lines, num_to_combine
  combo_indices = combigen(n_elements(emission_lines.wave), num_to_combine)
  combined_emission_lines = {wave:fltarr(num_to_combine), intensity:fltarr(1, n_elements(emission_lines.jd)), jd:emission_lines.jd, time_iso:emission_lines.time_iso}
  depths_combo = {wave:fltarr(num_to_combine, n_elements(combo_indices[*, 0])), depth:fltarr(n_elements(combo_indices[*, 0])), uncertainty:fltarr(n_elements(combo_indices[*, 0]))}
  FOR i = 0, n_elements(combo_indices[*, 0]) - 1 DO BEGIN
    waves = reform(emission_lines.wave[combo_indices[i, *]])
    
    FOR j = 0, num_to_combine - 1 DO BEGIN 
      combined_emission_lines.intensity += emission_lines.intensity[combo_indices[i, j], *]
    ENDFOR
    combined_emission_lines.wave = waves
    preflare_baseline_combo = estimate_preflare_baseline(combined_emission_lines)
    depth = get_dimming_depth(combined_emission_lines, preflare_baseline_combo.intensity)

    uncertainty_min = depth.uncertainty
    uncertainty_baseline = preflare_baseline_combo.uncertainty[0]
    uncertainty_depth = 100 * sqrt(uncertainty_min^2 * (1/preflare_baseline_combo.intensity)^2 + uncertainty_baseline^2 * depth.depth_over_squared_baseline^2) ; [%]

    depths_combo.wave[*, i] = waves
    depths_combo.depth[i] = depth.depth
    depths_combo.uncertainty[i] = uncertainty_depth
  ENDFOR
  return, depths_combo
END


FUNCTION plot_dimming_performance, depths, instrument, num_lines_to_combine
  uncertainty_lower = depths.depth - depths.uncertainty
  uncertainty_upper = depths.depth + depths.uncertainty
  ordered_indices = sort(depths.depth)
  p = plot(depths.depth[ordered_indices], font_size=16, thick=3, $
            xtitle='index of ' + strtrim(num_lines_to_combine, 2) + '-emission-line combination', $
            ytitle='dimming depth [%]', yrange=[0, 5], $
            title='ESCAPE CSR; exposure time = ' + jpmprintnumber(instrument.exposure_time_sec, /no_decimals) + ' seconds')
  poly = polygon([findgen(n_elements(ordered_indices)), reverse(findgen(n_elements(ordered_indices)))] , $
                 [uncertainty_lower[ordered_indices], reverse(uncertainty_upper[ordered_indices])], /DATA, /FILL_BACKGROUND, $
                 fill_color='light steel blue', transparency=50, linestyle='none')
  IF num_lines_to_combine EQ 1 THEN p.xtitle = 'index of single emission line'
  return, p
END