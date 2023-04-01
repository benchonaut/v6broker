#!/bin/bash
## hint: try  apt-get remove man-db mailcap manpages  xinetd exim4 apache2-bin cifs-utils apache2-data ftp  fetchmail apache2-doc
## hint: for userspace:  
## 1 get go e.g.      #  wget -O- -c https://go.dev/dl/go1.20.1.linux-amd64.tar.gz| tar -C /usr/local -xz;bash -c 'echo "export PATH=$PATH:/usr/local/go/bin" >> /etc/profile';
## 2 get wg userspace  #  ( cd /usr/src/; git clone https://github.com/WireGuard/wireguard-go.git ;export PATH=$PATH:/usr/local/go/bin;cd /usr/src/wireguard-go/;make && cp /usr/src/wireguard-go/wireguard-go /usr/bin )
## optional: wg-quick-go:  go install github.com/QuantumGhost/wg-quick-go@latest

clients=$NUM_CLIENTS


## TODO: fallback detection
## detect the address for clients to connect if not given 
[[ -z "$PUBLICFOUR" ]]  && PUBLICFOUR=$(curl -4 whatismyip.akamai.com);
## that is not necessarily the truth since there might be nat , split horizon etc

PORT=$PUBLIC_PORT
internalfour=$INTERNAL_FOUR
[[ -z "$internalfour" ]]  && internalfour=10.23.7.1/24
blankinternalfour=$(echo ${internalfour}|cut -d. -f1-3)
maskinternalfour=$(echo ${internalfour}|cut -d/ -f2)
myinternalfour=$blankinternalfour".1/"$maskinternalfour

[[ -z "$PORT" ]] && PORT=22400
scope=$SCOPE
[[ -z "$scope" ]]   && scope="v6broker"
[[ -z "$clients" ]] && clients="10"
 
#Public ( routed /48 or /64 )
## using private ipv6
[[ -z "$PREFIX" ]] && PREFIX=fdbe:1312:beef::/48
#[[ -z "$PREFIX" ]] && PREFIX=2001:470:ffff::/48

## mask is whatever you set in your prefix , you might take a routed /48 or a sub-range of a real interface
MASK=${PREFIX/*\//}
## we add 12 bits, eg. /48to /52 ,  /64 to /74 , /74 to /80
CLIENTMASK=$(($MASK+12))
## but more than 128 bit is not possible ( only one client )
[[ $CLIENTMASK -ge 128 ]] && CLIENTMASK=128
PREFIX_BLANK=${PREFIX//\/*/};

myaddr=${PREFIX_BLANK}":";
myaddr=$(echo "$myaddr"|sed 's/:::/::/g')
myaddr=${myaddr}"1"/$MASK
myvsix=${myaddr}

myaddr=$myaddr,$myinternalfour

echo "GEN CONFIG"
echo "PUBLIC   ip4: "$PUBLICFOUR
echo "PUBLIC  PORT: "$PORT

echo "PREFIX MASK6: "$MASK
echo "CLIENT MASK6: "$CLIENTMASK
echo "PREFIX  IPv6: "$PREFIX
echo "PREFIXb IPv6: "$PREFIX_BLANK
echo "WG INT 6ADDR: "$myvsix;

echo "CLIENT MASK4: "$maskinternalfour
echo "PREFIX  IPv4: "$blankinternalfour
echo "WG INT 4ADDR: "$myinternalfour;

echo "CONF_ADDR   : "$myaddr   
echo "SCOPE(NAME): "$scope

cd /etc/wireguard;
## genkey if not exists ##
test -e $scope.privkey||(wg genkey |tee $scope.privkey |wg pubkey > $scope.pubkey);
test -e ${scope}_clients || mkdir ${scope}_clients
for clientnum in $(seq 1 $clients);do  
    test -e ${scope}_clients||mkdir ${scope}_clients;  
      test -e ${scope}_clients/client$clientnum.privkey || (
         echo -n " genkey $clientnum " >&2 ; 
           wg genkey | tee ${scope}_clients/client$clientnum.privkey | wg pubkey > ${scope}_clients/client$clientnum.pubkey);
           test -e ${scope}_clients/client$clientnum.psk || (  echo -n " genpsk $clientnum "; wg genpsk > ${scope}_clients/client$clientnum.psk );
           done;
## config gen
myhead=$( 
         (echo '[Interface]';
          echo "ListenPort = $PORT";
          echo "#MTU = 1320";
          echo "#SaveConfig = false"; 
          echo "#Address = "$myaddr;
          echo "PrivateKey = "$(cat $scope.privkey);echo  );echo ;)
      mybody=""
for clientnum in $(seq 1 $clients);do  
  CLIENTSIX=${PREFIX//:\/$MASK/"$(($clientnum*110))"::1\/$CLIENTMASK}
  CLIENTFOUR=${blankinternalfour}"."$((100+$clientnum))"/"$maskinternalfour
  CLIENTADDR=${CLIENTSIX}
  CLIENTALLOW=${CLIENTSIX}
  [[ -z "$CLIENTFOUR" ]] ||  CLIENTADDR=${CLIENTSIX}","${CLIENTFOUR}
  [[ -z "$CLIENTFOUR" ]] || CLIENTALLOW=${CLIENTSIX}","${CLIENTFOUR/\/*/}"/32"

  test -e ${scope}_clients/client$clientnum.conf ||( 
     echo "genconf_client$clientnum  @ $CLIENTADDR" >&2;     
     ( echo '[Interface]';   
       echo "Address = "${CLIENTADDR} ;
       echo "MTU = 1320";
       echo "PrivateKey = "$(cat ${scope}_clients/client$clientnum.privkey);
       echo "[Peer]";
       echo "Endpoint = "${PUBLICFOUR}:${PORT};
       echo "AllowedIPs = ::0/0,0.0.0.0/0";
       echo "PublicKey = "$(cat  $scope.pubkey);
       echo "PreSharedKey = "$(cat ${scope}_clients/client$clientnum.psk );
       echo "PersistentKeepalive = 25"   
       ) > ${scope}_clients/client$clientnum.conf
     );
     
     mybody="$mybody"$(echo ; 
        echo '[Peer]
#client'$clientnum'
PublicKey = '$(cat ${scope}_clients/client$clientnum.pubkey )'
PreSharedKey = '$(cat ${scope}_clients/client$clientnum.psk )'
AllowedIPs = '${CLIENTALLOW}'
' ); 
done

echo "generating $scope.conf"
(echo "$myhead";echo ;echo "$mybody") > $scope.conf


mycmd=$(
echo "ip link add dev $scope type wireguard";
echo "wg setconf $scope /etc/wireguard/$scope.conf"
)
which wireguard-go && mycmd=$(
echo "wireguard-go $scope"
echo "wg setconf $scope /etc/wireguard/$scope.conf"
)

test -e /tmp/.privnet.py || (
echo "IyBjb2Rpbmc9dXRmOAojIHRoZSBhYm92ZSB0YWcgZGVmaW5lcyBlbmNvZGluZyBmb3IgdGhpcyBkb2N1bWVudCBhbmQgaXMgZm9yIFB5dGhvbiAyLnggY29tcGF0aWJpbGl0eQppbXBvcnQgc3lzCmltcG9ydCByZQoKcmVnZXggPSByIlxiKDEyN1wuKD86MjVbMC01XXwyWzAtNF1bMC05XXxbMDFdP1swLTldWzAtOV0/KVwuKD86MjVbMC01XXwyWzAtNF1bMC05XXxbMDFdP1swLTldWzAtOV0/KVwuKD86MjVbMC01XXwyWzAtNF1bMC05XXxbMDFdP1swLTldWzAtOV0/KXwwPzEwXC4oPzoyNVswLTVdfDJbMC00XVswLTldfFswMV0/WzAtOV1bMC05XT8pXC4oPzoyNVswLTVdfDJbMC00XVswLTldfFswMV0/WzAtOV1bMC05XT8pXC4oPzoyNVswLTVdfDJbMC00XVswLTldfFswMV0/WzAtOV1bMC05XT8pfDE3MlwuMD8xWzYtOV1cLig/OjI1WzAtNV18MlswLTRdWzAtOV18WzAxXT9bMC05XVswLTldPylcLig/OjI1WzAtNV18MlswLTRdWzAtOV18WzAxXT9bMC05XVswLTldPyl8MTcyXC4wPzJbMC05XVwuKD86MjVbMC01XXwyWzAtNF1bMC05XXxbMDFdP1swLTldWzAtOV0/KVwuKD86MjVbMC01XXwyWzAtNF1bMC05XXxbMDFdP1swLTldWzAtOV0/KXwxNzJcLjA/M1swMV1cLig/OjI1WzAtNV18MlswLTRdWzAtOV18WzAxXT9bMC05XVswLTldPylcLig/OjI1WzAtNV18MlswLTRdWzAtOV18WzAxXT9bMC05XVswLTldPyl8MTkyXC4xNjhcLig/OjI1WzAtNV18MlswLTRdWzAtOV18WzAxXT9bMC05XVswLTldPylcLig/OjI1WzAtNV18MlswLTRdWzAtOV18WzAxXT9bMC05XVswLTldPyl8MTY5XC4yNTRcLig/OjI1WzAtNV18MlswLTRdWzAtOV18WzAxXT9bMC05XVswLTldPylcLig/OjI1WzAtNV18MlswLTRdWzAtOV18WzAxXT9bMC05XVswLTldPyl8OjoxfFtmRl1bY0NkRF1bMC05YS1mQS1GXXsyfSg/Ols6XVswLTlhLWZBLUZdezAsNH0pezAsN318W2ZGXVtlRV1bODlhQWJCXVswLTlhLWZBLUZdKD86WzpdWzAtOWEtZkEtRl17MCw0fSl7MCw3fSkoPzpcLyhbNzg5XXwxP1swLTldezJ9KSk/XGIiCnRlc3Rfc3RyID0gKHN5cy5hcmd2WzFdKyJcbiIgKQptYXRjaGVzID0gcmUuZmluZGl0ZXIocmVnZXgsIHRlc3Rfc3RyLCByZS5NVUxUSUxJTkUpCmZvciBtYXRjaE51bSwgbWF0Y2ggaW4gZW51bWVyYXRlKG1hdGNoZXMsIHN0YXJ0PTEpOgogICAgcHJpbnQgKCJNYXRjaCB7bWF0Y2hOdW19IHdhcyBmb3VuZCBhdCB7c3RhcnR9LXtlbmR9OiB7bWF0Y2h9Ii5mb3JtYXQobWF0Y2hOdW0gPSBtYXRjaE51bSwgc3RhcnQgPSBtYXRjaC5zdGFydCgpLCBlbmQgPSBtYXRjaC5lbmQoKSwgbWF0Y2ggPSBtYXRjaC5ncm91cCgpKSkKIyAgICBmb3IgZ3JvdXBOdW0gaW4gcmFuZ2UoMCwgbGVuKG1hdGNoLmdyb3VwcygpKSk6CiMgICAgICAgIGdyb3VwTnVtID0gZ3JvdXBOdW0gKyAxCiMgICAgICAgIHByaW50ICgiR3JvdXAge2dyb3VwTnVtfSBmb3VuZCBhdCB7c3RhcnR9LXtlbmR9OiB7Z3JvdXB9Ii5mb3JtYXQoZ3JvdXBOdW0gPSBncm91cE51bSwgc3RhcnQgPSBtYXRjaC5zdGFydChncm91cE51bSksIGVuZCA9IG1hdGNoLmVuZChncm91cE51bSksIGdyb3VwID0gbWF0Y2guZ3JvdXAoZ3JvdXBOdW0pKSkKIyBOb3RlOiBmb3IgUHl0aG9uIDIuNyBjb21wYXRpYmlsaXR5LCB1c2UgdXIiIiB0byBwcmVmaXggdGhlIHJlZ2V4IGFuZCB1IiIgdG8gcHJlZml4IHRoZSB0ZXN0IHN0cmluZyBhbmQgc3Vic3RpdHV0aW9uLgo=" |base64 -d > /tmp/.privnet.py
)


( 
echo "$mycmd"
echo "#wg show"

## ipv4 NAT
echo 'iptables -L POSTROUTING -t nat -v -n  |grep MASQ |grep -q '$blankinternalfour".0/"$maskinternalfour' ||  ( 
   iptables -I POSTROUTING -t nat -s '$blankinternalfour".0/"$maskinternalfour' -j ACCEPT  ) '

## ipv4 wg→public (OUT_ONLY)
echo 'iptables -L FORWARD -v -n  |grep RELATED |grep -q '$scope' ||  ( 
   iptables -I FORWARD -m state --state NEW,RELATED,ESTABLISHED -i '$scope' -j ACCEPT ;iptables -I FORWARD -m state --state RELATED,ESTABLISHED -o '$scope' -j ACCEPT ) '
## ipv6 wg→public (OUT_ONLY)
echo 'ip6tables -L FORWARD -v -n  |grep RELATED |grep -q '$scope' ||  ( 
   iptables -I FORWARD -m state --state NEW,RELATED,ESTABLISHED -i '$scope' -j ACCEPT ;ip6tables -I FORWARD -m state --state RELATED,ESTABLISHED -o '$scope' -j ACCEPT ) '

## v6 specials
python3 /tmp/.privnet.py "$PREFIX"|grep -q ^Match || (
## A PUBLIC PREFIX WILL BE FORWARDED AND NOT NATTED
    echo 'ip6tables -L FORWARD -v -n|grep '$PREFIX' |grep ACCEPT ||     ip6tables  -I FORWARD -d '$PREFIX' -j ACCEPT'
)

  python3 /tmp/.privnet.py "$PREFIX"|grep -q ^Match && (
    ## A PRIVATE PREFIX WILL BE NATTED
    echo 'ip6tables -L POSTROUTING -t nat -v -n|grep '$PREFIX' | grep MASQ -q ||     ip6tables  -I POSTROUTING -s '$PREFIX' -t nat -j MASQUERADE'
  )
echo "sysctl -w net.ipv6.conf.all.forwarding=1"

 echo "ip -4 address add dev $scope $myinternalfour"
 echo "ip -6 address add dev $scope $myvsix"
 echo "ip link set up dev $scope"
 echo iptables -I INPUT -p udp --dport $PORT -j ACCEPT
) > /etc/wireguard/_start_$scope.sh

echo "now try bash /etc/wireguard/_start_$scope.sh"
