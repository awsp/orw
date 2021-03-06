#!/bin/bash

orw_conf=~/.config/orw/config
dunst_conf=~/.orw/dotfiles/.config/dunst/dunstrc
theme_conf=~/.orw/themes/theme/openbox-3/themerc
openbox_conf=~/.orw/dotfiles/.config/openbox/rc.xml
lock_conf=~/.orw/dotfiles/.config/i3lockrc
rofi_path=~/.orw/dotfiles/.config/rofi
rofi_list_conf=list

while getopts :c: flag; do
	case $flag in
		c)
			mode=$OPTARG
			[[ $3 =~ ^r ]] && mode+=.rasi

			shift 2;;
	esac
done

[[ ! $mode ]] &&
	mode=$(awk -F '"' 'END { print $(NF - 1) ".rasi" }' $rofi_path/main.rasi)

if [[ $2 =~ [0-9]+ ]]; then
	sign=${2%%[0-9]*}
	new_value=${2#"$sign"}
fi

case $1 in
	#[xy]*)
	#	awk -i inplace '{
	#		if(/^'${1:0:1}'_offset/) {
	#			nv = '$new_value'
	#			cv = gensub(".* ", "", 1)
	#			sub(cv, ("'$sign'") ? cv '$sign' nv : nv)
	#		}
	#		print
	#	}' ~/.config/orw/config;;

	w*)
		#[[ ${1:1:1} == [xy] ]] && pattern=${1:0:1}_offset || pattern=ratio
		#[[ ${1: -1} == [xy] ]] && pattern=${1: -1}_offset || pattern=ratio

		read property value <<< $(awk '/^'${1: -1}'/ { print; exit }' $orw_conf)

		if [[ $property =~ offset ]]; then
			[[ $(awk '/^offset/ { print $NF }' $orw_conf) == true ]] &&
				~/.orw/scripts/windowctl.sh -o -${property:0:1} $sign$new_value && exit
			min=0
		else
			read part ratio <<< $(awk '/^(part|ratio)/ { print $NF }' $orw_conf | xargs)
			min=1
		fi

		#[[ $property == part ]] && ratio=$(awk '/^ratio/ { print $NF }' $orw_conf)

		[[ $sign ]] && check_value=$((value $sign $new_value)) || check_value=$new_value

		#if ((check_value > 0 && (ratio && check_value < ratio || !ratio))); then
		if ((check_value >= min)); then
			#[[ $property == part && $check_value -ge $ratio ]] &&
			#	check_value=$value message="<b>${property^}</b> must be lower then <b>$ratio</b>"
			#[[ $property == ratio && $check_value -le $part ]] && $0 wp $((ratio / 2))

			message="<b>${property/_/ }</b> changed to <b>$check_value</b>"

			if [[ $property == part ]]; then
				[[ $check_value -lt $ratio ]] &&
					new_ratio="$check_value/$ratio" ||
					check_value=$part new_ratio="$part/$ratio" \
					message="<b>${property^}</b> must be lower then ratio (<b>$ratio</b>)"
			fi

			if [[ $property == ratio ]]; then
				if [[ $check_value -gt $part ]]; then
					new_ratio="$part/$check_value"
				else
					part=$((check_value / 2))
					new_ratio="$part/$check_value"

					$0 wp $part
				fi
			fi

			[[ ! $property =~ offset ]] && message+="\nCurrent ratio: <b>($new_ratio)</b>"

			sed -i "/$property/ s/$value/$check_value/" $orw_conf
		else
			#message="<b>${property^} cannot be changed further!"
			#message="<b>$check_value</b> is out of range <b>(1..$((ratio - 1)))</b>!"
			message="<b>$check_value</b> must be higher than <b>$min</b>!"
		fi

		#ratio=$(awk '/^(part|ratio)/ { if(!p) p = $NF; else { print p "/" $NF; exit } }' $orw_conf)
		[[ ! $3 ]] && ~/.orw/scripts/notify.sh -pr 22 "$message"
		exit
		#checking_value=$((value $sign $new_value))

		awk -i inplace '{
			if(/^'${1: -1}'/ && ! set) {
				set = 1
				nv = '$new_value'
				cv = gensub(".* ", "", 1)

				if("'$sign'") nrv = cv '$sign' nv
				if($1 == "part") max = '$ratio'

				sub(cv, (nrv > 0) ? nrv : nv)
			}

			print
		}' ~/.config/orw/config;;
	r*)
		if [[ $1 == rip ]]; then
			if [[ $3 ]]; then
				second_sign=${3%%[0-9]*}
				second_arg=${3#$second_sign}
			fi

			awk -i inplace '/inputbar|element/ { set = 1 } {
				if(/padding/ && set) {
					set = 0

					if(av) {
						if("'$mode'" ~ "dmenu") v2 = v1
					} else {
						fv = '$new_value'
						sv = '${second_arg-0}'
						av = gensub(".* ([0-9]+).* ([0-9]+).*", "\\1 \\2", 1)
						split(av, v)

						v1 = ("'$sign'") ? v[1] '$sign' fv : fv 
						v2 = (sv) ? ("'$second_sign'") ? v[2] '$second_sign' sv : sv : \
							("'$mode'" ~ "dmenu") ? v[2] : v1
					}

					gsub("[0-9]+px [0-9]+", v1 "px " v2)
				}
				print
			}' $rofi_path/$mode
		else
			case $1 in
				rf) pattern=font;;
				rw) pattern=width;;
				rr)
					set=2
					pattern=radius;;
				rim)
					px=px
					pattern=margin
					[[ $mode =~ dmenu ]] && pattern+=".* 0 .*";;
				rwp)
					px=px
				 	pattern=padding;;
				r*bw)
					px=px
					pattern="border:.*px"

					[[ $1 == ribw ]] && pattern="${pattern/\./.*0.}" rofi_conf=theme.rasi

					[[ $mode =~ list ]] && rofi_conf=theme.rasi;;
					#[[ ! $mode =~ dmenu|icons ]] && rofi_conf=theme.rasi;;
				rln)
					pattern=lines
					rofi_conf=config.rasi;;
				rsp) pattern=spacing;;
			esac

			awk -i inplace '\
				BEGIN { set = '${set:-1}' }
				{
					if(/'"$pattern"'/ && set) {
						px = "'$px'"
						nv = '$new_value'
						cv = gensub(".* ([0-9]*)" px ".*", "\\1", 1)
						sub(cv px, ("'$sign'") ? cv '$sign' nv px : nv px)
						set--
					}
				print
			}' $rofi_path/${rofi_conf:-$mode}

			#awk -i inplace '\
			#	{ if(/'"$pattern"'/ && ! set) {
			#		px = "'$px'"
			#		nv = '$new_value'
			#		cv = gensub(".* ([0-9]*)" px ".*", "\\1", 1)
			#		sub(cv px, ("'$sign'") ? cv '$sign' nv px : nv px)
			#		set = '${set-1}'
			#	}
			#	print
			#}' $rofi_path/${rofi_conf:-$mode}
		fi;;
	tm*)
		[[ $1 == tms ]] && pattern=separator || pattern='window.*format'

		awk -i inplace '
			function set_value() {
				cv = length(s)
				uv = "'${new_value:-$2}'"
				nv = sprintf("%*.s", ("'$sign'") ? cv '$sign' uv : uv, " ")
			}

			{
				if(/'$pattern'/) {
					if(!s) {
						w = (/format/)
						p = (w) ? ".*W" : ".*\""
						s = gensub(p "(.*)\"$", "\\1", 1)
					}

					set_value()

					if(w) {
						wp = (/current/) ? "W" : "I"
						$0 = gensub("( *)(#[" wp "]|\"$)", nv "\\2", "g")
					} else {
						sub(/".*"/, "\"" nv "\"")
					}
				}
			}
		{ print }' ~/.orw/dotfiles/.config/tmux/tmux.conf

		tmux source-file ~/.orw/dotfiles/.config/tmux/tmux.conf
		exit;;
	tp)
		awk -i inplace '\
			{
				if(/padding/) {
					nv = '$new_value'
					cv = gensub("[^0-9]*([0-9]+).*", "\\1", 1)
					sub(cv, ("'$sign'") ? cv '$sign' nv : nv)
				}
				print
		}' ~/.orw/dotfiles/.config/gtk-3.0/gtk.css;;
	tb*)
		ob_reload=true
		[[ $1 == tb ]] && pattern='name.*\*' nr=1 || pattern='font.*ActiveWindow' nr=2

		awk -i inplace '\
			/'$pattern'/ { nr = NR } { \
			if (nr && NR == nr + '$nr') {
				nv = "'${new_value:-$2}'"
				cv = gensub(".*>(.*)<.*", "\\1", 1)
				sub(cv, ('$nr' == 1) ? (nv) ? nv : (cv == "no") ? "yes" : "no" : ("'$sign'") ? cv '$sign' nv : nv)
			}
			print
		}' $openbox_conf;;
	d*)
		#[[ $1 == dp ]] && pattern=padding || pattern=frame_width
		[[ $mode ]] && dunst_conf="${dunst_conf%/*}/${mode}_dunstrc"

		if [[ $1 =~ df ]]; then
			pattern=frame_width
		else
			[[ $1 =~ h ]] && pattern=horizontal_
			pattern+=padding
		fi

		awk -i inplace '{ \
			if(/^\s*\w*'$pattern'/) {
				nv = '$new_value'
				sub($NF, ("'$sign'") ? $NF '$sign' nv : nv)
			}
			print
		}' $dunst_conf

		command=$(ps -C dunst -o args= | awk '{ if($1 == "dunst") $1 = "'$(which dunst)'"; print }')
		killall dunst
		$command &> /dev/null &;;
	l*)
		case $1 in
			lr) pattern=radius;;
			lts) pattern=timesize;;
			lds) pattern=datesize;;
			*) pattern=width
		esac

		awk -i inplace '{ \
			if(/^'$pattern'/) {
				nv = '$new_value'
				cv = gensub(".*=", "", 1)
				sub(cv, ("'$sign'") ? cv '$sign' nv : nv)
			}
			print
		}' $lock_conf;;
	*)
		ob_reload=true

		case $1 in
			hw) pattern=handle.width;;
			bw) pattern=^border.width;;
			cp) pattern='client.*padding';;
			ch) pattern='client.padding.height';;
			cw) pattern='client.padding.width';;
			jt) pattern=label.*justify;;
			pw) pattern=^padding.width;;
			ph) pattern=^padding.height;;
			md) pattern=^menu.overlap.x;;
			mbw)
				pattern=^menu.border.width
				gtkrc2=~/.orw/themes/theme/gtk-2.0/gtkrc;;
		esac

		awk -i inplace '{ \
			if("'$pattern'" ~ "menu") {
				if(/^menu.border/) obw = $NF
				if(/^menu.overlap/) {
					if("'$pattern'" ~ "border") $NF = (obw + $NF) - nv
				}
			}
			if(/'$pattern'/) {
				nv = '${new_value:-\"$2\"}'

				if(/overlap/) {
					if("'$sign'") {
						if("'$sign'" == "+") $NF -= nv; else $NF += nv
					} else {
						$NF = -(obw + nv)
					}
				} else {
					$NF = ("'$sign'") ? $NF '$sign' nv : nv
					nv = $NF
				}
			} if("'$pattern'" ~ "menu") { 
				if(/^style "menu"/) set = 2
				
				if(/thickness/ && set) {
					$NF = nv
					set--
				}
			}
			print
		}' $theme_conf $gtkrc2
esac

[[ $ob_reload ]] && openbox --reconfigure || exit 0
