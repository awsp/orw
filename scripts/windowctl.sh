#!/bin/bash

blacklist="Keyboard Status Monitor,DROPDOWN"

set_window_id() {
	id=$1

	read border_x border_y <<< $([[ $id =~ ^0x ]] && xwininfo -id $id | awk '\
		/Relative/ { if(/X/) x = $NF; else y = $NF + x } END { print 2 * x, y }')
}

function get_windows() {
	wmctrl -lG | awk '$2 == '$current_desktop' && ! /('"${blacklist//,/|}"')$/ && $1 ~ /'$1'/ \
		{ print $1, $3 - '${border_x:=0}', $4 - ('${border_y:=0}' - '$border_x' / 2) * 2, $5, $6 }'
}

function set_windows_properties() {
	[[ ! $properties ]] && properties=( $(get_windows $id) )

	[[ $1 == h ]] && index=1 || index=2
	get_display_properties $index

	if [[ ! $all_windows ]]; then
		while read -r wid wx wy ww wh; do
			if ((wx > display_x && wx + ww < display_x + width && wy > display_y && wy + wh < display_y + height)); then
				all_windows+=( "$wid $wx $wy $ww $wh" )
			fi
		done <<< $(get_windows)
	fi
}

function update_properties() {
	for window_index in "${!all_windows[@]}"; do
		[[ ${all_windows[window_index]%% *} == $id ]] && all_windows[window_index]="${properties[*]}"
	done
}

function generate_properties_format() {
	echo -n 0
	for property in ${properties[*]:1}; do echo -n ",$property"; done
}

function generate_printable_properties() {
	id=${1%% *}
	printable_properties=${1#* }
}

function save_properties() {
	#[[ -f $property_log ]] && echo $id $printable_properties >> $property_log
	echo $id $printable_properties >> $property_log
}

function backtrace_properties() {
	read line_number properties <<< $(awk '/^'$id'/ { nr = NR; p = substr($0, 12) } END { print nr, p }' $property_log)
	sed -i "${line_number}d" $property_log
	echo "$properties"
}

function restore_properties() {
	[[ -f $property_log ]] && properties=( $(grep "^$id" $property_log) )
}

function apply_new_properties() {
	[[ $printable_properties ]] && wmctrl -ir $id -e 0,${printable_properties// /,}
}

function list_all_windows() {
	for window in "${all_windows[@]}"; do
		echo $window
	done
}

function backup() {
	backup_properties="wmctrl -ir $id -e 0$(generate_properties_format original ${original_properties[*]})"

	if [[ -f $property_log && $(grep $id $property_log) ]]; then
		[[ $overwrite ]] && sed -i "s/.*$id.*/$backup_properties/" $property_log
	else
		echo "$backup_properties" >> $property_log
	fi
}

list_bars() {
	for bar in "${bars[@]}"; do
		echo $bar
	done
}

set_orientation_properties() {
	if [[ $1 == h ]]; then
		index=1
		dimension=width
		offset=$x_offset
		step=$font_width
		start=$display_x
		opposite_dimension=height
		opposite_start=$display_y
		border=${edge_border:-$border_x}
		bar_vertical_offset=0
	else
		index=2
		dimension=height
		offset=$y_offset
		step=$font_height
		start=$display_y
		opposite_dimension=width
		opposite_start=$display_x
		border=${edge_border:-$border_y}
		bar_vertical_offset=$((bar_top_offset + bar_bottom_offset))
	fi

	start_index=$((index % 2 + 1))
	end=$((start + ${!dimension:-0}))
	opposite_end=$((opposite_start + ${!opposite_dimension:-0}))
}

get_display_properties() {
	read display display_x display_y width height original_min_point original_max_point bar_min bar_max x y <<< \
		$(awk -F '[_ ]' '{ if(/^orientation/) {
			cd = 1
			bmin = 0
			d = '${display:-0}'
			i = '$1'; mi = i + 2
			wx = '${properties[1]}'
			wy = '${properties[2]}'

			if($NF ~ /^h/) {
				i = 3
				p = wx
			} else {
				i = 4
				p = wy
			}
		} {
			if($1 == "display") {
				if($3 == "xy") {
					cd = $2

					if((d && d == cd) || !d) {
						dx = $4
						dy = $5
						minp = $(mi + 1)
					}
				} else {
					if((d && d == cd) || !d) {
						dw = $3
						dh = $4
						maxp = minp + $mi
					}

					max += $i

					if((d && p < max && (cd >= d)) || (!d && p < max)) {
						print (d) ? d : cd, dx, dy, dw, dh, minp, maxp, bmin, bmin + dw, dx + wx, dy + wy
						exit
					} else {
						if(d && cd < d || !d) bmin += $3
						if(p > max) if(i == 3) wx -= $i
						else wy -= $i
					}
				}
			}
		}
	}' ~/.config/orw/config)
}

get_bar_properties() {
	if [[ ! $bars_checked ]]; then
		while read -r bar_name position bar_x bar_y bar_width bar_height adjustable_width frame; do
			current_bar_height=$((bar_y + bar_height))
			((position)) && (( current_bar_height += frame ))

			if ((position)); then
				((current_bar_height > bar_top_offset)) && bar_top_offset=$current_bar_height
			else
				((current_bar_height > bar_bottom_offset)) && bar_bottom_offset=$current_bar_height
			fi

			if [[ $1 == add && $bar_name ]]; then
				if ((adjustable_width)); then
					read bar_width bar_height bar_x bar_y < ~/.config/orw/bar/geometries/$bar_name
				else
					((!position)) && bar_y=$((display_y + height - (bar_y + bar_height)))
					(( bar_x -= bar_min ))
				fi

				[[ $bar_offset ]] && bar_x=$display_x bar_width=$width

				bar_properties="$bar_name $bar_x $bar_y $bar_width $bar_height $frame"
				all_windows+=( "$bar_properties" )
				bars+=( "$bar_properties" )
			fi
		done <<< $(~/.orw/scripts/get_bar_info.sh $display)
	fi

	bars_checked=true
}

set_base_values() {
	set_windows_properties $1

    original_properties=( ${properties[*]} )

	set_orientation_properties $1

	unset edge_border

	properties[1]=$x
	properties[2]=$y

	update_properties

	if [[ $option == tile ]]; then
		original_properties[1]=$x
		original_properties[2]=$y
	fi

	[[ $option != tile ]] && min_point=$((original_min_point + offset))

	get_bar_properties add
}

function set_sign() {
	sign=${1:-+}
	[[ $sign == + ]] && opposite_sign="-" || opposite_sign="+"
}

function resize() {
	edge=$1

	(( properties[$index + 2] ${sign}= value ))
	[[ $edge =~ [lt] ]] && (( properties[$index] ${opposite_sign}= value ))

	[[ $adjucent && $edge =~ [rt] ]] && reverse_adjucent=-r
}

function resize_to_edge() {
	index=$1
	offset=$2

	((index > 1)) && border=$border_y || border=$border_x

	if [[ $argument =~ [BR] ]]; then
		properties[$index + 2]=$((${max:-$end} - offset - ${properties[$index]} - border))
	else
		properties[$index + 2]=$((${properties[$index]} + ${properties[$index + 2]} - max - offset))
		properties[$index]=$((${max:-$start} + offset))
	fi
}


function calculate_size() {
	[[ $denominator -eq 1 ]] && window_margin=0 || window_margin=${margin:-$offset}

	[[ $dimension =~ [[:alpha:]]+ ]] && dimension=${!dimension}

	available_size=$((dimension - bar_vertical_offset - 2 * offset - (denominator - 1) * window_margin - denominator * border))
	window_size=$((available_size / denominator))

	[[ $option == move ]] && ((numerator--))

	size=$(((numerator * window_size) + (numerator - 1) * (window_margin + border)))

	if [[ $option == move ]]; then
		[[ $argument == v ]] && bar_offset=$bar_top_offset || bar_offset=0
		start_point=$((start + bar_offset + offset + size + border + window_margin))
	else
		if ((numerator == denominator)); then
			size=$available_size
			start_point=$min_point
		else
			start_point=$((min_point + size + border + window_margin))
		fi
	fi

	end_point=$((start_point + window_size))
}

sort_windows() {
	list_all_windows | awk \
		'{
			i = '$index' + 1
			d = (i == 2)
			sc = $i

			if($1 == "'$id'") {
				if("'$1'" ~ /[BRbr]/) sc += '${properties[index + 2]}'
			} else {
				if("'$1'" ~ /[LTlt]/) sc = $i + $(i + 2)
			}

			print sc, $0
		}' | sort $reverse -nk 1
}

tile() {
	local window_count

	max_point=$original_max_point
	min_point=$((original_min_point + offset))

	while read wid w_min w_max; do
		if [[ $id != $wid ]]; then
			[[ ! $wid =~ ^0x ]] && distance=$offset ||
				distance=$((${margin:-$offset} + border))

			if ((min_point == offset)); then
				if [[ $wid =~ ^0x ]]; then
					if ((w_min == min_point)); then
						min_point=$((w_max + distance))
						((window_count++))
					else
						max_point=$w_min && break
					fi
				else
					#((window_count)) && max_point=$w_min || 
					#	min_point=$((w_max + distance))
					if ((!window_count)); then
						min_point=$((w_max + distance))
					else
						max_point=$w_min
						break
					fi
				fi
			else
				if ((w_min > min_point)); then
					if [[ ! $wid =~ ^0x && ! $window_count ]]; then
						min_point=$((w_max + distance))
					else 
						max_point=$w_min
						break
					fi
				else
					((w_max + distance > min_point)) && min_point=$((w_max + distance))
				fi
			fi
		else
			((window_count++))
		fi
	done <<< $(list_all_windows | awk '
			BEGIN {
				si = '$start_index' + 1
				cws = '${properties[start_index]}'
				cwe = cws + '${properties[start_index + 2]}'
			} {
				ws = $si; we = ws + $(si + 2)
				if ((ws >= cws && ws <= cwe) ||
					(we >= cws && we <= cwe) ||
					(ws <= cws && we >= cwe)) print $0
			}' | sort -nk $((index + 1)),$((index + 1)) -nk $((start_index + 1)) | awk '
				function assign(w_index) {
					bb = ($1 ~ "0x") ? 0 : $NF
					i = (w_index) ? w_index : (l) ? l : 1
					mix_a[i] = $1 " " $pi " " $pi + $(pi + 2) + bb
				}

				BEGIN { pi = '$index' + 1 }
				{
					if(NR == 1) {
						assign()
					} else {
						l = length(mix_a)
						split(mix_a[l], mix)

						if($pi == mix[2]) {
							if($pi + $(pi + 2) > mix[3]) assign()
						} else {
							assign(l + 1)
						}
					}
				}
				END { for (w in mix_a) { print mix_a[w] } }')

	if ((${properties[index]} != min_point ||
		${properties[index]} + ${properties[index + 2]} != max_point)); then
		#((max_point < original_max_point && wid != max_point)) && [[ ! $wid =~ ^0x ]] && 
		((max_point < original_max_point)) && [[ $wid =~ ^0x ]] && 
			local last_offset=$margin

		if [[ $orientation == h ]]; then
			win_x=$min_point
			win_y=${original_properties[2]}
			win_width=$((max_point - min_point - ${last_offset:-$offset} - border))
			win_height=${original_properties[4]}
		else
			win_x=${original_properties[1]}
			win_y=$min_point
			win_width=${original_properties[3]}
			win_height=$((max_point - min_point - ${last_offset:-$offset} - border))
		fi

		properties=( $id $win_x $win_y $win_width $win_height )
	else
		properties=( ${original_properties[*]} )
	fi
}

tile_adjucent() {
	((index == 1)) && orientation=h || orientation=v

	old_properties=( ${original_properties[*]} )

	for property_index in {1..4}; do
		new_property=${properties[property_index]}
		old_property=${old_properties[property_index]}
		((new_property != old_property)) && break
	done

	((property_index > 2)) && ra=-r

	option=tile
	set_base_values $orientation

	get_adjucent() {
		local reverse=$2
		local properties=( $1 )

		sort_windows | sort -n $reverse | awk '\
			BEGIN {
				r = "'$reverse'"
				i = '$index' + 2
				si = '$start_index' + 2
				o = '${margin:-$offset}' + '$border'

				id = "'${properties[0]}'"
				cwsp = '${properties[index]}'
				cwep = '${properties[index]}' + '${properties[index + 2]}'
				cws = '${properties[start_index]}'
				cwe = '${properties[start_index]}' + '${properties[start_index + 2]}'
				
				c = (r) ? cwep + o : cwsp - o
			} {
				if($2 ~ "0x" && $2 != "'$original_id'") {
					if($2 == id) exit
					else {
						ws = $si
						we = ws + $(si + 2)
						cp = (r) ? $i : $i + $(i + 2)

						if((cp == c) &&
							((ws >= cws && ws <= cwe) ||
							(we >= cws && we <= cwe) ||
							(ws <= cws && we >= cwe))) print
					}
				}
			}'
	}

	add_adjucent_window() {
		properties=( $1 )
		id=${properties[0]}
		original_properties=( ${properties[*]} )

		tile

		update_properties
		adjucent_windows+=( "${properties[*]}" )
	}

	find_neighbour() {
		while read -r c window; do
			if [[ $c ]]; then
				add_adjucent_window "$window"

				[[ $2 ]] && ra='' || ra=-r
				original_id=${1%% *}
				find_neighbour "$window" $ra
			fi
		done <<< $(get_adjucent "$1" $2)
	}

	find_neighbour "${old_properties[*]}" $ra
	for window in "${adjucent_windows[@]}"; do
		generate_printable_properties "$window"
		apply_new_properties
	done
}

add_offset() {
	[[ ! -f $offsets_file ]] && touch $offsets_file

	if [[ "$arguments" =~ -o ]]; then
		 eval $(awk '/^'$1'=/ {
			e = 1
			cv = gensub("[^0-9]*", "", 1)
			sub("[0-9]+", ("'${!1}'" ~ "[+-]") ? cv '${!1}' : '${!1}')
		} { o = o "\n" $0 }
			END {
				if(!e) o = o "\n'$1=${!1}'"
				print o | "xargs"
				print substr(o, 2)
			}' $offsets_file | { read -r o; { printf "%s\n" "$o" >&1; cat > $offsets_file; } })

		~/.orw/scripts/notify.sh -pr 22 "<b>${1/_/ }</b> changed to <b>${!1}</b>"
	fi
}

get_optarg() {
	((argument_index++))
	optarg=${!argument_index}
}

get_neighbour_window_properties() {
	local index reverse direction=$1

	[[ $direction =~ [lr] ]] && index=1 || index=2
	[[ $direction =~ [br] ]] && reverse=-r
	[[ $tiling ]] && local first_field=2

	start_index=$((index % 2 + 1))

	read -a second_window_properties <<< \
		$(sort_windows $direction | sort $reverse -nk 1,1 | awk \
			'{ cwp = '${properties[index]}'; cwsp = '${properties[start_index]}'; \
			if("'$direction'" ~ /[br]/) cwp += '${properties[index + 2]}'; \
				wp = $1; wsp = $('$start_index' + 2); xd = (cwsp - wsp) ^ 2; yd = (cwp - wp) ^ 2; \
				print sqrt(xd + yd), $0 }' | sort -nk 1,1 | awk 'NR == 2 \
				{ if(NF > 7) { $6 += ($NF - '$border_x'); $7 += ($NF - '$border_y')}
				print gensub("([^ ]+ ){" '${first_field-3}' "}|" $8 "$)", "", 1) }')
}

print_wm_properties() {
	(( wm_properties[0] -= display_x ))
	(( wm_properties[1] -= display_y ))
	echo $display ${wm_properties[*]}
}

resize_by_ratio() {
	local argument=$1
	local orientation=$2
	local ratio=$3

	#[[ ${!argument_index} =~ ^[1-9] ]] && ratio=${!argument_index} && shift
	#[[ $orientation =~ r$ ]] && orientation=${orientation:0:1} reverse=true ||
	#	reverse=$(awk '/^reverse/ { print $NF }' $config)
	[[ $orientation =~ r$ ]] && orientation=${orientation:0:1} reverse=true

	if [[ ${orientation:0:1} == a ]]; then
		((${properties[3]} > ${properties[4]})) && orientation=h || orientation=v
		((ratio)) || ratio=$(awk '/^(part|ratio)/ { if(!p) p = $NF; else { print p "/" $NF; exit } }' $config)
		#((ratio)) || ratio=$(awk '/^(part|ratio)/ { if(!r) r = $NF; else { print $NF "/" r; exit } }' $config)

		auto_tile=true
		argument=H
	fi

	set_orientation_properties $orientation

	[[ ${ratio:=2} =~ / ]] && part=${ratio%/*} ratio=${ratio#*/}

	[[ $argument == D ]] && op1=* op2=+ || op1=/ op2=-
	[[ $orientation == h ]] && direction=x || direction=y

	if ((!separator)); then
		border=border_$direction
		offset=${direction}_offset
		separator=$(((${!border} + ${margin:-${!offset}})))
	fi

	original_start=${properties[index]}
	original_property=${properties[index + 2]}

	if [[ $argument == H || $part ]]; then
		portion=$((original_property - (ratio - 1) * separator))
		(( portion /= ratio ))

		if [[ $part ]]; then
			(( portion *= part ))
			(( portion += (part - 1) * separator ))
		fi

		if [[ $argument == H ]]; then
			properties[index + 2]=$portion
			[[ $reverse == true ]] && (( properties[index] += original_property - portion ))
		else
			(( properties[index + 2] += portion + separator ))
			[[ $reverse == true ]] && (( properties[index] -= portion + separator ))
		fi
	else
		portion=$(((original_property + separator) * (ratio - 1)))
		(( properties[index + 2] += portion ))
		[[ $reverse == true ]] && (( properties[index] -= portion ))
	fi

	read -a wm_properties <<< $(awk '{
		r = "'$reverse'"
		s = '$separator'
		o = "'$display_orientation'"

		p = $('$index' + 3) + s
		$('$index' + 3) = '$original_property' - p
		$('$index' + 1) = (r == "true") ? '$original_start' : $('$index' + 1) + p
		print gensub(/[^ ]* /, "", 1)
	}' <<< "${properties[*]}")
}

set_alignment_direction() {
	[[ $1 == h ]] &&
		index=1 opposite_index=2 direction=x opposite_direction=v display_property=$display_x ||
		index=2 opposite_index=1 direction=y opposite_direction=h display_property=$display_y

	border=border_$direction
	offset=${direction}_offset
	separator=$(((${!border} + ${margin:-${!offset}})))
}

get_alignment() {
	[[ $1 ]] && local current_direction=$1_

	set_alignment_direction ${1:-$align_direction}

	read ${current_direction}alignment_start ${current_direction}alignment_area ${current_direction}alignment_ratio \
		${current_direction}aligned_window_count ${current_direction}aligned_windows <<< \
		$(list_all_windows | sort -nk $((index + 1)),$((index + 1)) | \
			awk '\
				function is_aligned(win1, win2) {
					delta = (win1 > win2) ? win1 - win2 : win2 - win1
					return delta < wc
				}

				BEGIN {
					i = '$index'
					s = '$separator'
					oi = '$opposite_index'
					wc = '${#all_windows[*]}'
					d = '${properties[index + 2]}'
					od = '${properties[opposite_index + 2]}'
					p = '${properties[opposite_index]}'
				}

				$(oi + 1) == p && od == $(oi + 3) && is_aligned(d, $(i + 3)) {
					na = aa && $(i + 1) - s != as + aa

					if(!length(aa) || na) {
						if(na && c) exit
						as = $(i + 1)
						aa = $(i + 3)
						aw = ""
						awc = 0
					} else {
						aa += s + $(i + 3)
					}

					if($1 == "'$id'") c = 1

					aw = aw " \"" $0 "\""
					awc++
				} END { print as, aa, aa / od, awc, aw }')
}

select_window() {
	color=$(awk -Wposix -F '#' '/\.active.border/ { 
		r = sprintf("%d", "0x" substr($NF, 1, 2)) / 255
		g = sprintf("%d", "0x" substr($NF, 3, 2)) / 255
		b = sprintf("%d", "0x" substr($NF, 5, 2)) / 255
		print r "," g "," b }' ~/.orw/themes/theme/openbox-3/themerc)

	read -a second_window_properties <<< $( \
		slop -n -b $((border_x / 2)) -c $color -f '%i %x %y %w %h' | awk '{
			$1 = sprintf("0x%.8x", $1)
			x = '$border_x'
			y = '$border_y'
			$2 -= (x / 2)
			$3 -= (y / 2)
			print
		}')
}

align() {
	read mode align_direction reverse <<< $(awk '{
		if(/^mode/) m = $NF
		else if(/^reverse/) r = ($NF == "true") ? "r" : ""
		else if(/^direction/) print m, $NF, r }' $config)

	[[ $optarg =~ c$ ]] && close=true
	[[ $optarg && $optarg != c ]] && align_direction=${optarg:0:1}

	if [[ $mode == selection ]]; then
		select_window

		(( second_window_properties[0] -= display_x ))
		(( second_window_properties[1] -= display_y ))

		read x y w h <<< ${second_window_properties[*]}
		~/.orw/scripts/set_geometry.sh -c '\\\*' -x $x -y $y -w $w -h $h
		exit
	elif [[ $id == none ]]; then
		get_bar_properties
		read width height <<< $(awk '/^display_'${display-1}' / { print $2, $3 }' $config)

		border=$(awk '/^border/ { print $NF * 2 }' ~/.orw/themes/theme/openbox-3/themerc)

		#~/.orw/scripts/notify.sh "$x_offset $((y_offset + bar_top_offset)) $((width - 2 * x_offset - border)) $((height - (bar_top_offset + bar_bottom_offset) - 2 * y_offset - border))"
		~/.orw/scripts/set_geometry.sh -c '\\\*' -x $x_offset -y $((y_offset + bar_top_offset)) \
			-w $((width - 2 * x_offset - border)) -h $((height - (bar_top_offset + bar_bottom_offset) - 2 * y_offset - border))
	else
		if [[ ! $all_windows ]]; then
			set_windows_properties $display_orientation
			set_orientation_properties $display_orientation
		fi

		if [[ ( $mode == auto || ${#all_windows[*]} -eq 1 ) && ! $close ]]; then
			if [[ $mode == stack ]]; then
				[[ $align_direction == h ]] && align_direction=v || align_direction=h
			elif [[ $mode == auto ]]; then
				ratio=$(awk '/^(part|ratio)/ { if(!p) p = $NF; else { print p "/" $NF; exit } }' $config)
			fi

			#resize_by_ratio ${resize_argument:-H} $align_direction$reverse
			resize_by_ratio H $align_direction$reverse $ratio

			generate_printable_properties "${properties[*]}"
			apply_new_properties

			read x y w h <<< ${wm_properties[*]}
			~/.orw/scripts/set_geometry.sh -c '\\\*' -x $((x - display_x)) -y $((y - display_y)) -w $w -h $h
		else
			if [[ $mode == stack && ! $close ]]; then
				[[ $align_direction == h ]] && align_index=3 || align_index=2
				properties=( $(list_all_windows | sort -nk $align_index,$align_index | tail -1) )
			fi

			if [[ $close ]]; then
				if [[ $mode != auto ]]; then
					get_alignment h
					get_alignment v
				fi

				if [[ $mode == auto ]] || ((h_aligned_window_count + v_aligned_window_count <= 2)); then
					get_closest_windows() {
						set_alignment_direction $1

						local start=${properties[opposite_index]}
						local end=$((start + ${properties[opposite_index + 2]}))

						read $1_size $1_aligned_windows <<< $(list_all_windows | sort -nk $index,$index | awk '\
							function set_current_window() {
								cp = p
								cd = d
								cid = "\"" $0 "\""
								dis = (p < ws) ? ws - (p + $('$index' + 2)) : p - we
							}

							BEGIN {
								ws = '${properties[index]}'
								we = ws + '${properties[index + 2]}'
							}

							$1 != "'$id'" {
								p = $('$index' + 1)
								s = $('$opposite_index' + 1)
								d = $('$opposite_index' + 3)
								e = s + d

								if(s >= '$start' && e <= '$end') {
									if(cp) {
										if(cp == p) {
											cd += d
											cid = cid " \"" $0 "\""
										} else if(cd >= max && (!md || dis < md)) {
											max = cd
											md = dis
											id = cid
											mp = p
											set_current_window()
										}
									} else {
										set_current_window()
									}
								}
							} END { print (cd >= max && (!md || dis < md)) ? cd " " cid : max " " id }')
					}

					get_closest_windows h
					get_closest_windows v
					
					((h_size > v_size)) &&
						dominant_alignment=h aligned_windows="$h_aligned_windows" ||
						ominant_alignment=v aligned_windows="$v_aligned_windows"

					set_alignment_direction $dominant_alignment
					eval aligned=( "$aligned_windows" )
					wmctrl -ic $id

					align_size=$((${properties[index + 2]} + separator))

					for window in "${aligned[@]}"; do
						properties=( $window )
						id=${properties[0]}

						(( properties[index + 2] += align_size ))

						generate_printable_properties "${properties[*]}"
						apply_new_properties
					done
					exit
				else
					if ((h_aligned_window_count == v_aligned_window_count)); then
						dominant_alignment=$(echo $h_alignment_ratio $v_alignment_ratio | awk '{ print ($1 < $2) ? "h" : "v" }')
					else
						((h_aligned_window_count > v_aligned_window_count)) && dominant_alignment=h || dominant_alignment=v
					fi
				fi

				set_alignment_direction $dominant_alignment

				[[ $dominant_alignment == h ]] &&
					alignment_start=$h_alignment_start alignment_area=$h_alignment_area aligned_windows=$h_aligned_windows ||
					alignment_start=$v_alignment_start alignment_area=$v_alignment_area aligned_windows=$v_aligned_windows

				aligned_windows="${aligned_windows/\"${properties[*]}\"/}" 
				wmctrl -ic $id
			else
				get_alignment
			fi

			eval aligned=( "$aligned_windows" )
			aligned_count="${#aligned[@]}"

			[[ $close ]] &&
				align_size=$(((alignment_area - (aligned_count - 1) * separator) / aligned_count)) ||
				align_size=$(((alignment_area - aligned_count * separator) / (aligned_count + 1)))

			for window_index in "${!aligned[@]}"; do
				properties=( ${aligned[window_index]} )

				if ((window_index)); then
					 properties[index]=$next_window_start
				 else
					 #[[ $reverse ]] && (( properties[index] += align_size + separator )) || properties[index]=$alignment_start
					 [[ ! $reverse || $close ]] &&
						 properties[index]=$alignment_start || (( properties[index] += align_size + separator ))
				fi

				[[ $close || $reverse ]] && ((window_index == aligned_count - 1)) &&
					original_align_size=$align_size align_size=$((alignment_start + alignment_area - ${properties[index]}))

				properties[index + 2]=$align_size
				next_window_start=$((${properties[index]} + ${properties[index + 2]} + separator))

				#echo ${properties[*]}
				generate_printable_properties "${properties[*]}"
				apply_new_properties
			done

			if [[ ! $close ]]; then
				if [[ $reverse ]]; then
					properties[index]=$alignment_start
					properties[index + 2]=$original_align_size
				else
					properties[index]=$next_window_start
					properties[index + 2]=$((alignment_area - (aligned_count * (align_size + separator))))
				fi

				read x y w h <<< ${properties[*]:1}
				~/.orw/scripts/set_geometry.sh -c '\\\*' -x $((x - display_x)) -y $((y - display_y)) -w $w -h $h
			fi
		fi
	fi

	exit



	#list_all_windows | sort -nk $((index + 1)),$((index + 1)) | \
	#	awk '\
	#		function is_aligned(win1, win2) {
	#			delta = (win1 > win2) ? win1 - win2 : win2 - win1
	#			return delta < wc
	#		}

	#		BEGIN {
	#			i = '$index'
	#			s = '$separator'
	#			oi = '$opposite_index'
	#			wc = '${#all_windows[*]}'
	#			d = '${properties[index + 2]}'
	#			od = '${properties[opposite_index + 2]}'
	#			p = '${properties[opposite_index]}'
	#		}

	#		$(oi + 1) == p && od == $(oi + 3) && is_aligned(d, $(i + 3)) {
	#			na = aa && $(i + 1) - s != as + aa

	#			if($1 == "'$id'") c = 1

	#			if(!length(aa) || na) {
	#				if(na && c) exit
	#				as = $(i + 1)
	#				aa = $(i + 3)
	#				aw = ""
	#			} else {
	#				aa += s + $(i + 3)
	#			}

	#			aw = aw " \"" $0 "\""
	#		} END { print as, aa, aw }'

	exit










	#list_all_windows | awk '\
	#	function is_aligned(win1, win2) {
	#		d = (win1 > win2) ? win1 - win2 : win2 - win1
	#		return d < wc
	#	}

	#	BEGIN {
	#		w = '${properties[3]}'
	#		h = '${properties[4]}'
	#		wc = '${#all_windows[*]}'
	#	}

	#	$1 != "'$id'" && is_aligned(w, $4) && is_aligned(h, $5)'
	#exit







	[[ $optarg =~ c$ ]] && close=true

	read mode align_direction reverse <<< $(awk '{
		if(/^mode/) m = $NF
		else if(/^reverse/) r = ($NF == "true") ? "r" : ""
		else if(/^direction/) print m, $NF, r }' $config)

	[[ $optarg && $optarg != c ]] && align_direction=${optarg:0:1}
	[[ $align_direction == h ]] &&
		index=1 opposite_index=2 direction=x opposite_direction=v display_property=$display_x ||
		index=2 opposite_index=1 direction=y opposite_direction=h display_property=$display_y

	#[[ $optarg =~ c$ ]] && resize_argument=D || resize_argument=H

	if [[ $mode == auto || ${#all_windows[*]} -eq 1 ]]; then
		[[ $mode == auto ]] && align_direction=a
		[[ $mode == stack ]] && unset reverse
		#resize_by_ratio ${resize_argument:-H} ${opposite_direction:-$align_direction}$reverse
		#resize_by_ratio ${resize_argument:-H} $align_direction$reverse

		resize_by_ratio ${resize_argument:-H} $align_direction$reverse

		generate_printable_properties "${properties[*]}"
		apply_new_properties

		#(( properties[index + 2] -= separator ))
		#(( properties[index + 2] /= 2 ))

		read x y w h <<< ${wm_properties[*]}
		~/.orw/scripts/set_geometry.sh -c '\\\*' -x $((x - display_x)) -y $((y - display_y)) -w $w -h $h

		#generate_printable_properties "${properties[*]}"
		#apply_new_properties

		#print_wm_properties
	else
		if [[ $mode == stack ]]; then
			align_index=$((opposite_index + 1))
			properties=( $(list_all_windows | sort -nk $align_index,$align_index | tail -1) )
		fi

		[[ $close ]] && unset reverse

		#eval aligned=( $(list_all_windows | awk '{
		#		w = '${properties[3]}'
		#		h = '${properties[4]}'
		#		p = '${properties[opposite_index]}'
		#	}
		#	$('$opposite_index' + 1) == p && $4 == w && $5 == h { print "\"" $0 "\"" }' | \
		#		sort -n${reverse}k $((index + 1)),$((index + 1))) )

		#read alignment_start whole_area aligned_windows <<< \
		#	$(list_all_windows | sort -n${reverse}k $((index + 1)),$((index + 1)) | \
		#		awk '{
		#			w = '${properties[3]}'
		#			h = '${properties[4]}'
		#			p = '${properties[opposite_index]}'
		#		}
		#		$('$opposite_index' + 1) == p && $4 == w && $5 == h {
		#			if(!length(as)) as = $('$index' + 1)
		#			aw = aw " \"" $0 "\""
		#		} END { print as, $('$index' + 3) + $('$index' + 1) - as, aw }')

		read alignment_start aligned_area aligned_windows <<< \
			$(list_all_windows | sort -nk $((index + 1)),$((index + 1)) | \
				awk '\
					BEGIN {
						i = '$index'
						oi = '$opposite_index'
						d = '${properties[index + 2]}'
						od = '${properties[opposite_index + 2]}'
						p = '${properties[opposite_index]}'
					}
					$(oi + 1) == p && od == $(oi + 3) && $(i + 3) - d <= awc++ {
						if(!length(as)) as = $(i + 1)
						aw = aw " \"" $0 "\""
					} END { print as, $(i + 1) + $(i + 3) - as, aw }')

		#eval aligned=( "${aligned_windows/${properties[*]}}" )
		if [[ $close ]]; then
			aligned_windows="${aligned_windows/\"${properties[*]}\"/}" 
			#close_command="wmctrl -ic $id"
			wmctrl -ic $id
		fi

		eval aligned=( "$aligned_windows" )

		aligned_count="${#aligned[@]}"
		#[[ $optarg =~ c$ ]] &&
		#	ratio=$((aligned_count + 1))/$aligned_count ||
		#	ratio=$aligned_count/$((aligned_count + 1))

		if ((!separator)); then
			border=border_$direction
			offset=${direction}_offset
			separator=$(((${!border} + ${margin:-${!offset}})))
		fi

		#[[ $optarg =~ ^c ]] &&
			#d_count=$((aligned_count + 1)) h_count=$aligned_count ||
			#d_count=$aligned_count h_count=$((aligned_count - 1)) ||
			#d_count=$((aligned_count - 1)) h_count=$aligned_count
		#[[ ! $optarg =~ c$ ]] && d_count=$((aligned_count - 1)) h_count=$aligned_count
		#[[ ! $optarg =~ c$ ]] && count_offset=1

		#align_size=$((aligned_area - (aligned_count - count_offset) * (${properties[index + 2]} + separator)))
		#align_size=$((aligned_area - (aligned_count - count_offset) * (align_size + separator)))

		[[ $close ]] &&
			align_size=$(((aligned_area - (aligned_count - 1) * separator) / aligned_count)) ||
			align_size=$(((aligned_area - aligned_count * separator) / (aligned_count + 1)))

		for window_index in "${!aligned[@]}"; do
			properties=( ${aligned[window_index]} )

			if ((window_index)); then
				 properties[index]=$next_window_start
			 else
				 [[ $reverse ]] && (( properties[index] += align_size + separator )) || properties[index]=$alignment_start
			fi

			#if [[ $reverse ]]; then
			#	original_align_property=${properties[index]}
			#	[[ $wm_properties ]] && properties[index]=$((${wm_properties[index - 1]} + ${wm_properties[index + 1]} - ${properties[index + 2]}))
			#else
			#	#[[ $wm_properties ]] && properties[index]=${wm_properties[index - 1]}
			#	((window_index)) && properties[index]=$next_window_start || properties[index]=$alignment_start
			#fi

			#((window_index)) || properties[index]=$alignment_start

			#resize_by_ratio H $align_direction${reverse} $ratio

			#(( properties[index + 2] += (aligned_count - count_offset) * (${properties[index + 2]} + separator) ))

			#properties[index + 2]=$aligned_area
			#resize_by_ratio H $align_direction$reverse $((aligned_count + count_offset))

			#((window_index == aligned_count - 1)) &&
			#	align_size=$((aligned_area - (alignment_start + aligned_area - ${properties[index]})))
			#	#align_size=$((aligned_area - (window_index * (align_size + separator))))

			[[ $close || $reverse ]] && ((window_index == aligned_count - 1)) &&
				align_size=$((alignment_start + aligned_area - ${properties[index]}))
				#align_size=$((aligned_area - ((aligned_count - 1) * (align_size + separator))))

			properties[index + 2]=$align_size
			next_window_start=$((${properties[index]} + ${properties[index + 2]} + separator))


			#if [[ $optarg =~ ^c ]]; then
			#	(( properties[index + 2] += aligned_count * ${properties[index + 2]} + separator) ))
			#else
			#	(( properties[index + 2] += (aligned_count - 1) * (${properties[index + 2]} + separator) ))
			#	resize_by_ratio H $align_direction$reverse $((aligned_count + 1))
			#	#(( properties[index + 2] -= aligned_count * separator ))
			#	#(( properties[index + 2] /= aligned_count + 1 ))


			##(( properties[index + 2] += (aligned_count - 1) * (${properties[index + 2]} + separator) ))
			##(( properties[index + 2] -= aligned_count * (${properties[index + 2]} + separator) ))

			#	#resize_by_ratio D $align_direction${reverse} $aligned_count
			##	resize_by_ratio H $align_direction${reverse} $((aligned_count + 1))
			#fi

			#echo ${properties[*]}
			generate_printable_properties "${properties[*]}"
			apply_new_properties
		done

		if [[ ! $close ]]; then
			if [[ $reverse ]]; then
				properties[index]=$alignment_start
				properties[index + 2]=$align_size
			else
				properties[index]=$next_window_start
				properties[index + 2]=$((aligned_area - (aligned_count * (align_size + separator))))
			fi

			read x y w h <<< ${properties[*]:1}
			~/.orw/scripts/set_geometry.sh -c '\\\*' -x $((x - display_x)) -y $((y - display_y)) -w $w -h $h
		fi
	fi

	#align_size=$((aligned_area - (aligned_count * (align_size + separator))))
	#echo $next_window_start $align_size
	exit
			#align_size=$((aligned_area - (window_index * (align_size + separator))))

		#echo $aligned_count
		#echo $alignment_start $aligned_area
		#echo ${properties[index]}
		#exit

		wm_properties[index + 1]=${properties[index + 2]}
		[[ $reverse ]] && wm_properties[index - 1]=$original_align_property
		print_wm_properties
		$close_command
	#fi
}

arguments="$@"
argument_index=1
options='(resize|move|tile)'

config=~/.config/orw/config
offsets_file=~/.config/orw/offsets
property_log=~/.config/orw/windows_properties

[[ ! -f $config ]] && ~/.orw/scripts/generate_orw_config.sh
[[ ! $current_desktop ]] && current_desktop=$(xdotool get_desktop)

read display_count {x,y}_offset display_orientation <<< $(awk '\
	/^display_[0-9]/ { dc++ } /[xy]_offset/ { offsets = offsets " " $NF } /^orientation/ { o = substr($NF, 1, 1) }
	END { print dc / 2, offsets, o }' $config)

[[ -f $offsets_file && $(awk '/^offset/ { print $NF }' $config) == true ]] && eval $(cat $offsets_file | xargs)
[[ ! $arguments =~ -[in] ]] && set_window_id $(printf "0x%.8x" $(xdotool getactivewindow))

while ((argument_index <= $#)); do
	argument=${!argument_index#-}
	((argument_index++))

	if [[ $argument =~ $options ]]; then
		[[ $option ]] && previous_option=$option
		option=$argument

		if [[ $option == tile ]]; then
			arguments=${@:argument_index}
			orientations="${arguments%%[-mr]*}"
			((argument_index += (${#orientations} + 1) / 2))

			set_windows_properties $display_orientation

			if [[ ! $orientations ]]; then
				window_x=$(wmctrl -lG | awk '$1 == "'$id'" { print $3 }')
				width=$(awk '/^display/ { width += $2; if ('$window_x' < width) { print $2; exit } }' $config)

				orientations=$(list_all_windows | sort -nk 2,4 -uk 2 | \
					awk '$1 ~ /^0x/ && $1 != "'$id'" {
						xo = '$x_offset'
						xb = '$border_x'
						m = '${margin:-$x_offset}'
						if(!x) x = '$display_x' + xo

						if($2 >= x) {
							x = $2 + $4 + xb + m
							w += $4; c++
						}
					} END {
						mw = '$width' - ((2 * xo) + (c * xb) + (c - 1) * m)
						if(mw - 1 > w && mw > w) print "h v"; else print "v h"
					}')
			fi

			for orientation in $orientations; do
				set_base_values $orientation
				tile
			done
		else
			[[ ! $previous_option =~ (resize|move) ]] && set_base_values $display_orientation
		fi
	else
		optarg=${!argument_index}
		[[ $argument =~ ^[SMCATRBLHDtrblhvjxymoidsrcp]$ &&
			! $optarg =~ ^(-[A-Za-z]|$options)$ ]] && ((argument_index++))

		case $argument in
			C) select_window;;
			A)
				align
				exit;;
			[TRBLHD])
				if [[ ! $option ]]; then
					if [[ $argument == R ]]; then
						set_windows_properties $display_orientation

						while read -r id properties; do
							printable_properties=$(backtrace_properties)
							apply_new_properties
						done <<< $(list_all_windows)
						exit
					else
						current_desktop=$optarg

						if [[ ! $properties ]]; then
							id=$(get_windows | awk 'NR == 1 { print $1 }')
							set_windows_properties
						fi
					fi
				else
					[[ $argument =~ [LR] ]] && set_orientation_properties h || set_orientation_properties v
					[[ $argument =~ [BR] ]] && reverse='-r' || reverse=''

					# ADDED DIMENSION TO SONRTING CRITERIA
					# Peace of code until the first sort command formats properties so it could be appropriatelly
					# compared with current window properties, by sorting all windows before/after current one,
					# depending on choosen direction.
					# ##NOTE! In case of D/R, current window sorting criteria(property which is compared with other windows)
					# is incremented by height/width, respectively.
					# After first sort we have only windows before/arter current window.
					# We are setting index, depending on direction, and start index, for opposite orientation.
					# Then we set all current window properties, and properties of window we are currently looking at,
					# as well as their min and max points, so we can eliminate windows from another screen.
					# After that condition, we are checking if window is blocking current window opposite orientation,
					# so we can move/resize it toward that window.

					max=$(sort_windows $argument | \
						awk '{
								if($2 == "'$id'") exit
								else {
									i = '$index' + 2
									si = '$start_index' + 2
									cws = '${properties[start_index]}'
									cwe = cws + '${properties[start_index + 2]}'
									ws = $si; we = ws + $(si + 2)
									wm = $i; b = ($2 ~ /^0x/) ? '$border' : $7

									if((ws >= cws && ws <= cwe) ||
										(we >= cws && we <= cwe) ||
										(ws <= cws && we >= cwe)) {
											max = ("'$argument'" ~ /[BR]/) ? wm : wm + $(i + 2) + b
											print max
										}
									}
								}' | tail -1)

					[[ $argument =~ [LR] ]] && offset_orientation=x_offset || offset_orientation=y_offset
					((!max || (max == bar_top_offset || max == bar_bottom_offset))) && offset=${!offset_orientation} ||
						offset=${margin:-${!offset_orientation}}

					case $argument in
						L) [[ $option == resize ]] && resize_to_edge 1 $offset || 
							properties[1]=$((${max:-$start} + offset));;
						T) [[ $option == resize ]] && resize_to_edge 2 $offset || 
							properties[2]=$((${max:-$start} + offset));;
						R) [[ $option == resize ]] && resize_to_edge 1 $offset ||
							properties[1]=$((${max:-$end} - offset - ${properties[3]} - border_x));;
						B) [[ $option == resize ]] && resize_to_edge 2 $offset ||
							properties[2]=$((${max:-$end} - offset - ${properties[4]} - border_y));;
						*)
							[[ ${!argument_index} =~ ^[1-9] ]] && ratio=${!argument_index} && shift
							resize_by_ratio $argument $optarg $ratio

							#[[ $optarg =~ r$ ]] && optarg=${optarg:0:1} reverse=true ||
							#	reverse=$(awk '/^reverse/ { print $NF }' $config)

							#if [[ ${optarg:0:1} == a ]]; then
							#	((${properties[3]} > ${properties[4]})) && optarg=h || optarg=v
							#	((ratio)) ||
							#		#ratio=$(awk '/^(part|ratio)/ { if(!p) p = $NF; else { print p "/" $NF; exit } }' $config)
							#		ratio=$(awk '/^(part|ratio)/ { if(!r) r = $NF; else { print $NF "/" r; exit } }' $config)

							#	auto_tile=true
							#	argument=H
							#fi

							#set_orientation_properties $optarg

							##[[ ${!argument_index} =~ ^[2-9/]+$ ]] && ratio=${!argument_index} && shift || ratio=2

							##if [[ ${!argument_index} =~ ^[2-9] ]]; then
							##	ratio=${!argument_index}
							##	shift
							##else
							##	ratio=2
							##fi

							#[[ ${ratio:=2} =~ / ]] && part=${ratio%/*} ratio=${ratio#*/}

							#[[ $argument == D ]] && op1=* op2=+ || op1=/ op2=-
							#[[ $optarg == h ]] && direction=x || direction=y

							#border=border_$direction
							#offset=${direction}_offset
							#separator=$(((${!border} + ${margin:-${!offset}})))

							#original_start=${properties[index]}
							#original_property=${properties[index + 2]}
							##total_separation=$(((ratio - 1) * (${!border} + ${!offset})))

							##(( properties[index + 2] $op2= (ratio - 1) * separator ))
							##(( properties[index + 2] $op1= ratio ))

							##[[ $argument == H ]] && (( properties[index + 2] -= (ratio - 1) * separator ))
							##(( properties[index + 2] $op1= ratio ))
							##[[ $argument == D ]] && (( properties[index + 2] += (ratio - 1) * separator ))

							#if [[ $argument == H || $part ]]; then
							#	portion=$((original_property - (ratio - 1) * separator))
							#	(( portion /= ratio ))

							#	#(( properties[index + 2] -= (ratio - 1) * separator ))
							#	#(( properties[index + 2] /= ratio ))

							#	if [[ $part ]]; then
							#		(( portion *= part ))
							#		(( portion += (part - 1) * separator ))
							#	fi

							#	#[[ $argument == D ]] && size_direction=- && (( portion += separator ))

							#	#properties[index + 2]=$portion
							#	#[[ $reverse ]] && (( properties[index] ${size_direction:-+}= original_property - (portion ) ))





							#	if [[ $argument == H ]]; then
							#		properties[index + 2]=$portion
							#		[[ $reverse == true ]] && (( properties[index] += original_property - portion ))
							#	else
							#		#[[ $argument == D ]] && (( properties[index + 2] += separator + original_property ))
							#		(( properties[index + 2] += portion + separator ))
							#		[[ $reverse == true ]] && (( properties[index] -= portion + separator ))
							#	fi





							#	#[[ $reverse ]] && (( properties[index] ${size_direction:-+}= portion + separator ))

							#	#if [[ $argument == H ]]; then
							#	#	[[ $reverse ]] && (( properties[index] += portion + separator ))
							#	#else
							#	#	#[[ $argument == D ]] && (( properties[index + 2] += separator + original_property ))
							#	#	properties[index + 2]=$((portion + separator))
							#	#	[[ $reverse ]] && (( properties[index] -= portion + separator ))
							#	#fi
							#else
							#	#(( properties[index + 2] *= ratio ))
							#	#(( properties[index + 2] += (ratio - 1) * separator ))
							#	portion=$(((original_property + separator) * (ratio - 1)))
							#	(( properties[index + 2] += portion ))
							#	[[ $reverse == true ]] && (( properties[index] -= portion ))
							#fi

							#if [[ $auto_tile ]]; then
							#	#read $reverse tiling_properties <<< $(awk '{
							#	awk '{
							#			d = '$display'
							#			x = '$display_x'
							#			y = '$display_y'
							#			r = "'$reverse'"
							#			s = '$separator'
							#			o = "'$display_orientation'"

							#			$('$index' + 1) -= (o == "h") ? x : y

							#			p = $('$index' + 3) + s
							#			$('$index' + 3) = '$original_property' - p
							#			$('$index' + 1) = (r == "true") ? '$original_start' : $('$index' + 1) + p
							#			sub(/[^ ]* /, "")
							#			print d, $0
							#		}' <<< "${properties[*]}"

							#	#((reverse_property)) && (( properties[index] += reverse_property ))
							#	#echo ${tiling_properties[*]}
							#fi
					esac

					update_properties
					unset max
				fi;;
			[hv])
				set_orientation_properties $argument

				if [[ $optarg =~ / ]]; then
					numerator=${optarg%/*}
					denominator=${optarg#*/}
					calculate_size
				fi

				if [[ $option == move ]]; then
					[[ $edge =~ [br] ]] && properties[index]=$((end_point - properties[index + 2])) ||
						properties[index]=${start_point:-$optarg}
				else
					if [[ $edge ]]; then
						set_sign +
						option=move
						calculate_size
						option=resize

						[[ $edge =~ [lt] ]] && value=$((properties[index] - start_point)) ||
							value=$((end_point - (properties[index] + properties[index + 2])))

						resize $edge $value
					else
						properties[index + 2]=${size:-$optarg}
					fi
				fi

				update_properties;;
			c)
				orientation=$optarg

				set_base_values $display_orientation

				for orientation in ${orientation:-h v}; do
					if [[ $orientation == h ]]; then
						properties[1]=$((display_x + (width - (${properties[3]} + border_x)) / 2))
					else
						y=$((display_y + bar_top_offset))
						bar_vertical_offset=$((bar_top_offset + bar_bottom_offset))
						properties[2]=$((y + ((height - bar_vertical_offset) - (${properties[4]} + border_y)) / 2))
					fi
				done

				update_properties;;
			i) set_window_id $optarg;;
			n)
				name="$optarg"
				id=$(wmctrl -lG | awk '$NF ~ "'$name'" { print $1 }')

				if [[ $id ]]; then
					set_window_id $id
					properties=( $(get_windows $id) )
				else
					#set_windows_properties $display_orientation
					#id="$name"
					get_bar_properties add
					properties=( $(list_all_windows | grep "$name") )
					#set_windows_properties $display_orientation
				fi;;
			D) current_desktop=$optarg;;
			d) display=$optarg;;
			[trbl])
				if [[ ! $option ]]; then
					case $argument in
						b) bar_offset=true;;
						r)
							properties=( $id $(backtrace_properties) )
							update_properties;;
						t)
							##align_direction=v
							##reverse=true

							##[[ $reverse ]] && reverse_align=-r

							#set_windows_properties $display_orientation
							#set_orientation_properties $display_orientation

							#read mode align_direction opposite_direction index opposite_index display_property reverse <<< \
							#	$(awk '{
							#		if(/^mode/) m = $NF
							#		else if(/^reverse/) r = ($NF == "true") ? "r" : ""
							#		else if(/^direction/) {
							#			p = ($NF == "h") ? "v 1 2 '$display_x'" : "h 2 1 '$display_y'"
							#			print m, $NF, p, r
							#		}
							#	}' $config)

							#if [[ $mode == auto || ${#all_windows[*]} -eq 1 ]]; then
							#	[[ $mode == auto ]] && align_direction=a
							#	[[ $mode == stack ]] && unset reverse
							#	resize_by_ratio H ${opposite_direction:-$align_direction}$reverse

							#	generate_printable_properties "${properties[*]}"
							#	apply_new_properties

							#	print_wm_properties
							#else
							#	if [[ $mode == stack ]]; then
							#		align_index=$((opposite_index + 1))
							#		properties=( $(list_all_windows | sort -nk $align_index,$align_index | tail -1) )
							#	fi

							#	eval aligned=( $(list_all_windows | awk '{
							#			w = '${properties[3]}'
							#			h = '${properties[4]}'
							#			p = '${properties[opposite_index]}'
							#		}
							#		$('$opposite_index' + 1) == p && $4 == w && $5 == h { print "\"" $0 "\"" }' | \
							#			sort -n${reverse}k $((index + 1)),$((index + 1))) )

							#	aligned_count="${#aligned[@]}"
							#	ratio=$aligned_count/$((aligned_count + 1))

							#	for window in "${aligned[@]}"; do
							#		properties=( $window )

							#		if [[ $reverse ]]; then
							#			original_align_property=${properties[index]}
							#			[[ $wm_properties ]] && properties[index]=$((${wm_properties[index - 1]} + ${wm_properties[index + 1]} - ${properties[index + 2]}))
							#		else
							#			[[ $wm_properties ]] && properties[index]=${wm_properties[index - 1]}
							#		fi

							#		resize_by_ratio H $align_direction${reverse} $ratio

							#		generate_printable_properties "${properties[*]}"
							#		apply_new_properties
							#	done

							#	wm_properties[index + 1]=${properties[index + 2]}
							#	[[ $reverse ]] && wm_properties[index - 1]=$original_align_property
							#	print_wm_properties
							#	#echo ${wm_properties[*]}
							#fi

							tiling=true

							set_windows_properties $display_orientation
							set_orientation_properties $display_orientation

							[[ $second_window_properties ]] || get_neighbour_window_properties $optarg

							original_id=$id
							properties=( ${second_window_properties[*]} )

							resize_by_ratio H a

							generate_printable_properties "${properties[*]}"
							apply_new_properties

							properties=( $original_id ${wm_properties[*]} )

							#new_properties=( $original_id $(align | cut -d ' ' -f 2-) )

							#(( new_properties[1] += display_x ))
							#(( new_properties[2] += display_y ))

							#properties=( ${new_properties[*]} )

							#echo ${properties[*]}

							#new_properties=( $original_id $(align) )

							#properties=( $id ${new_properties[*]:1} )

							#new_properties=( $($0 -i ${second_window_properties[0]} resize -H a$optarg) )
							#properties=( $id ${new_properties[*]:1} )
					esac
				else
					value=${optarg#*[-+]}
					set_sign ${optarg%%[0-9]*}

					[[ $argument =~ [lr] ]] && set_orientation_properties h || set_orientation_properties v

					if [[ $option == move ]]; then
						property=${properties[index]}
						dimension=${properties[index + 2]}

						[[ $argument =~ [br] ]] && direction=+ || direction=-

						((property $direction value < start + offset && display_count > 1)) && 
							properties[index + index_offset]=$((start - offset - dimension - border)) ||
							(( properties[index + index_offset] $direction= value ))

						((property $direction value > end - offset - dimension - border && display_count > 1)) &&
							properties[index + index_offset]=$((end + offset))
					else
						resize $argument
					fi

					update_properties
				fi;;
			g)
				set_windows_properties $display_orientation
				set_orientation_properties $display_orientation
				get_bar_properties

				while read -r window_properties; do
						grid_windows+=( "$window_properties" )
				done <<< $(list_all_windows | sort -nk 3)

				window_count=${#grid_windows[*]}
				max_window_count=$window_count

				if((window_count == 1)); then
					rows=1
					columns=1
				elif((window_count % 3 == 0)); then
					columns=3
					rows=$((window_count / 3))
				elif((window_count < 5)); then
					rows=$((window_count / 2))
					columns=$((window_count / rows))
				else
					max_window_count=$window_count

					while ((max_window_count % 3 > 0)); do
						((max_window_count++))
					done

					rows=3
					middle_row=$(((rows / 2) + 1))

					columns=$((max_window_count / rows))
					middle_row_columns=$((window_count % columns))
				fi

				calculate() {
					[[ $1 == width ]] && set_orientation_properties h || set_orientation_properties v

					calculate_size

					[[ $option == resize ]] && echo $size || echo $start_point
				}

				numerator=1

				option=resize

				denominator=$columns
				window_width=$(calculate width)

				denominator=$rows
				window_height=$(calculate height)

				option=move

				denominator=$((columns * 2))
				numerator=$((denominator / (middle_row_columns + 1)))

				middle_start=$(calculate width)

				for row in $(seq 0 $((rows - 1))); do
					window_y=$((display_y + bar_top_offset + y_offset + row * (window_height + border_y + ${margin:-$y_offset})))

					if ((row + 1 == middle_row)); then
						row_columns=$middle_row_columns
						x_start=$middle_start
					else
						row_columns=$columns
						x_start=$x_offset
					fi

					for column in $(seq 0 $((row_columns - 1))); do
						id=${grid_windows[window_index]%% *}

						window_x=$((display_x + x_start + column * (window_width + border_x + ${margin:-$x_offset})))

						printable_properties="$window_x $window_y $window_width $window_height"
						apply_new_properties

						((window_index++))
					done
				done

				exit;;
			M)
				set_windows_properties $display_orientation
				set_orientation_properties $display_orientation

				optind=${!argument_index}

				get_bar_properties add

				if [[ $second_window_properties ]]; then
					second_window_properties=( ${second_window_properties[*]:1} )
					optind=$optarg
				else
					case $optarg in
						[trbl])
							get_neighbour_window_properties $optarg;;
							#second_window_properties=( $(get_neighbour_window_properties $optarg) );;
							#[[ $optarg =~ [lr] ]] && index=1 || index=2
							#[[ $optarg =~ [br] ]] && reverse=-r

							#start_index=$((index % 2 + 1))
							#second_window_properties=( $(sort_windows $optarg | sort $reverse -nk 1,1 | awk \
							#	'{ cwp = '${properties[index]}'; cwsp = '${properties[start_index]}'; \
							#	if("'$optarg'" ~ /[br]/) cwp += '${properties[index + 2]}'; \
							#		wp = $1; wsp = $('$start_index' + 2); xd = (cwsp - wsp) ^ 2; yd = (cwp - wp) ^ 2; \
							#		print sqrt(xd + yd), $0 }' | sort -nk 1,1 | awk 'NR == 2 \
							#		{ if(NF > 7) { $6 += ($NF - '$border_x'); $7 += ($NF - '$border_y')}
							#		print gensub("(.*" $3 "|" $8 "$)", "", "g") }') );;
						*)
							[[ $optarg =~ ^0x ]] && mirror_window_id=$optarg ||
								mirror_window_id=$((wmctrl -l && list_bars) |\
								awk '{
									wid = (/^0x/) ? $NF : $1
									if(wid == "'$optarg'") {
										print $1
										exit
									}
								}')

							second_window_properties=( $(list_all_windows | \
								awk '$1 == "'$mirror_window_id'" {
									if(NF > 5) { $4 += ($NF - '${border_x:=0}'); $5 += ($NF - '${border_y:=0}') }
										print gensub("(" $1 "|" $6 "$)", "", "g") }') )
					esac
				fi

				if [[ $optind && $optind =~ ^[xseywh,+-/*0-9]+$ ]]; then
					for specific_mirror_property in ${optind//,/ }; do 
						unset operation operand additional_{operation,operand} mirror_value

						case $specific_mirror_property in
							x*) second_window_property_index=0;;
							y*) second_window_property_index=1;;
							w*) second_window_property_index=2;;
							h*) second_window_property_index=3;;
						esac

						if [[ ${specific_mirror_property:1:1} =~ [se] ]]; then
							mirror_border=border_${specific_mirror_property:0:1}

							if [[ $specific_mirror_property =~ ee ]]; then
								mirror_value=$((second_window_properties[second_window_property_index] + (${second_window_properties[second_window_property_index + 2]} - ${properties[second_window_property_index + 3]})))
							else
								[[ ${specific_mirror_property:1:1} == s ]] &&
									mirror_value=$((second_window_properties[second_window_property_index] - (${properties[second_window_property_index + 3]} + ${!mirror_border:-0}))) ||
									mirror_value=$((second_window_properties[second_window_property_index] + (${second_window_properties[second_window_property_index + 2]} + ${!mirror_border:-0})))
							fi
						fi

						if [[ $specific_mirror_property =~ [+-/*] ]]; then
							read operation operand additional_operation additional_operand<<< \
								$(sed 's/\w*\(.\)\([^+-]*\)\(.\)\?\(.*\)/\1 \2 \3 \4/' <<< $specific_mirror_property)
							((operand)) &&
								mirror_value=$((${mirror_value:-${second_window_properties[second_window_property_index]}} $operation operand))
							((additional_operand)) &&
								mirror_value=$((${mirror_value:-${second_window_properties[second_window_property_index]}} $additional_operation additional_operand))

							if [[ $specific_mirror_property =~ [+-]$ ]]; then
								((properties[second_window_property_index + 1] ${specific_mirror_property: -1}= ${mirror_value:-${second_window_properties[second_window_property_index]}}))
								continue
							fi
						fi

						properties[second_window_property_index + 1]=${mirror_value:-${second_window_properties[second_window_property_index]}}
					done

					shift
				elif ((${#second_window_properties[*]})); then
					index_property=${properties[index]}

					properties=( $id )
					properties+=( ${second_window_properties[*]:0:index - 1} )
					properties+=( $index_property )
					properties+=( "${second_window_properties[*]:index}" )
				else
					echo "Mirror window wasn't found in specified direction, please try another direction.."
				fi

				update_properties;;
			x)
				x_offset=$optarg
				add_offset x_offset;;
			y)
				y_offset=$optarg
				add_offset y_offset;;
			m)
				margin=$optarg
				add_offset margin;;
			o) [[ -f $offsets_file ]] && eval $(cat $offsets_file | xargs);;
			e) edge=$optarg;;
			[Ss])
				if [[ $option == move ]]; then
					[[ $optarg =~ [br] ]] && reverse=-r || start_reverse=r
					set_windows_properties $display_orientation
					set_orientation_properties $display_orientation

					[[ $optarg =~ [lr] ]] && index=1 start_index=2 || index=2 start_index=1

					swap_windwow_properties=( $(sort_windows $optarg | sort $reverse -nk 1,1 | \
						awk '{ si = '$start_index'; sp = $(si + 2); csp = '${properties[start_index]}'; \
						print (csp > sp) ? csp - sp : sp - csp, $0 }' | sort $reverse -nk 2,2 -nk 1,1$start_reverse | \
						awk '{ if($3 == "'$id'") { print p; exit } else { gsub(/.*0x/, "0x", $0); p = $0 } }') )

					original_properties=( ${properties[*]} )
					printable_properties="${swap_windwow_properties[*]:1}"

					apply_new_properties
					id=${swap_windwow_properties[0]}
					printable_properties="${original_properties[*]:1}"

					apply_new_properties
					exit
				else
					set_windows_properties $display_orientation

					if [[ $argument == S ]]; then
						while read -r id printable_properties; do
							save_properties
						done <<< $(list_all_windows)
					else
						generate_printable_properties "${properties[*]}"
						save_properties
					fi
				fi;;
			p)
				if ((${#properties[*]} > 5)); then
					[[ $display_orientation == h ]] && index=1 || index=2
					get_display_properties $index
					awk '{
						if(NF > 5 && $3 < 0) $3 += '$display_y' + '$height'
						print
					}' <<< ${properties[*]}
				else
					if [[ $second_window_properties ]]; then
						[[ ! $properties ]] && properties=( ${second_window_properties[*]} )

						[[ $display_orientation == h ]] && index=1 || index=2
						get_display_properties $index

						properties=( ${properties[*]:1} )

						(( properties[0] -= display_x ))
						(( properties[1] -= display_y ))
					fi

					echo -n "$border_x $border_y "
					[[ $properties ]] && echo ${properties[*]} ||
						get_windows ${id:-$name} | cut -d ' ' -f 2-
				fi
				exit;;
			o) overwrite=true;;
			a) adjucent=true;;
			?) continue;;
		esac
	fi
done

generate_printable_properties "${properties[*]}"
apply_new_properties

if [[ $adjucent ]]; then
	tile_adjucent
fi
