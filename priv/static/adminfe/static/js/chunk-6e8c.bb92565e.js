(window.webpackJsonp=window.webpackJsonp||[]).push([["chunk-6e8c"],{"13xp":function(e,s,t){"use strict";var r=t("2r4G");t.n(r).a},"2r4G":function(e,s,t){},"4bFr":function(e,s,t){"use strict";t.r(s);var r=t("ot3S"),i=t("tPM3"),a=t("o0o1"),n=t.n(a),o=t("yXPU"),u=t.n(o),l=t("XJYT"),c={name:"SecuritySettingsModal",props:{visible:{type:Boolean,default:!1},user:{type:Object,default:function(){return{}}}},data:function(){return{securitySettingsForm:{newEmail:"",newPassword:"",isEmailLoading:!1,isPasswordLoading:!1}}},computed:{isDesktop:function(){return"desktop"===this.$store.state.app.device},getLabelWidth:function(){return this.isDesktop?"120px":"85px"},userCredentials:function(){return this.$store.state.userProfile.userCredentials}},mounted:function(){var e=u()(n.a.mark(function e(){return n.a.wrap(function(e){for(;;)switch(e.prev=e.next){case 0:return e.next=2,this.$store.dispatch("FetchUserCredentials",{nickname:this.user.nickname});case 2:this.securitySettingsForm.newEmail=this.userCredentials.email;case 3:case"end":return e.stop()}},e,this)}));return function(){return e.apply(this,arguments)}}(),methods:{updateEmail:function(){var e=this;return u()(n.a.mark(function s(){var t;return n.a.wrap(function(s){for(;;)switch(s.prev=s.next){case 0:return t={email:e.securitySettingsForm.newEmail},e.securitySettingsForm.isEmailLoading=!0,s.next=4,e.$store.dispatch("UpdateUserCredentials",{nickname:e.user.nickname,credentials:t});case 4:e.securitySettingsForm.isEmailLoading=!1,Object(l.Message)({message:e.$t("userProfile.securitySettings.emailUpdated"),type:"success",duration:5e3});case 6:case"end":return s.stop()}},s)}))()},updatePassword:function(){var e=this;return u()(n.a.mark(function s(){var t;return n.a.wrap(function(s){for(;;)switch(s.prev=s.next){case 0:return t={password:e.securitySettingsForm.newPassword},e.securitySettingsForm.isPasswordLoading=!0,s.next=4,e.$store.dispatch("UpdateUserCredentials",{nickname:e.user.nickname,credentials:t});case 4:e.securitySettingsForm.isPasswordLoading=!1,e.securitySettingsForm.newPassword="",Object(l.Message)({message:e.$t("userProfile.securitySettings.passwordUpdated"),type:"success",duration:5e3});case 7:case"end":return s.stop()}},s)}))()},close:function(){this.$emit("close",!0)}}},d=(t("13xp"),t("KHd+")),p=Object(d.a)(c,function(){var e=this,s=e.$createElement,t=e._self._c||s;return t("el-dialog",{staticClass:"security-settings-modal",attrs:{"before-close":e.close,title:e.$t("userProfile.securitySettings.securitySettings"),visible:e.visible}},[t("el-form",{attrs:{model:e.securitySettingsForm,"label-width":e.getLabelWidth}},[t("el-form-item",{attrs:{label:e.$t("userProfile.securitySettings.email")}},[t("el-input",{attrs:{placeholder:e.$t("userProfile.securitySettings.inputNewEmail")},model:{value:e.securitySettingsForm.newEmail,callback:function(s){e.$set(e.securitySettingsForm,"newEmail",s)},expression:"securitySettingsForm.newEmail"}})],1),e._v(" "),t("el-form-item",[t("el-button",{staticClass:"security-settings-submit-button",attrs:{loading:e.securitySettingsForm.isEmailLoading,disabled:!e.securitySettingsForm.newEmail||e.securitySettingsForm.newEmail===e.userCredentials.email,type:"primary"},on:{click:function(s){return e.updateEmail()}}},[e._v("\n        "+e._s(e.$t("userProfile.securitySettings.submit"))+"\n      ")])],1),e._v(" "),t("el-form-item",{staticClass:"password-input",attrs:{label:e.$t("userProfile.securitySettings.password")}},[t("el-input",{attrs:{placeholder:e.$t("userProfile.securitySettings.inputNewPassword")},model:{value:e.securitySettingsForm.newPassword,callback:function(s){e.$set(e.securitySettingsForm,"newPassword",s)},expression:"securitySettingsForm.newPassword"}}),e._v(" "),t("small",{staticClass:"form-text"},[e._v("\n        "+e._s(e.$t("userProfile.securitySettings.passwordLengthNotice",{minLength:8}))+"\n      ")])],1),e._v(" "),t("el-alert",{staticClass:"password-alert",attrs:{closable:!1,type:"warning","show-icon":""}},[t("p",[e._v(e._s(e.$t("userProfile.securitySettings.passwordChangeWarning1")))]),e._v(" "),t("p",[e._v(e._s(e.$t("userProfile.securitySettings.passwordChangeWarning2")))])]),e._v(" "),t("el-form-item",[t("el-button",{staticClass:"security-settings-submit-button",attrs:{loading:e.securitySettingsForm.isPasswordLoading,disabled:e.securitySettingsForm.newPassword.length<8,type:"primary"},on:{click:function(s){return e.updatePassword()}}},[e._v("\n        "+e._s(e.$t("userProfile.securitySettings.submit"))+"\n      ")])],1)],1)],1)},[],!1,null,null,null);p.options.__file="SecuritySettingsModal.vue";var g=p.exports,v=t("rIUS"),_=t("WjBP"),m={name:"UsersShow",components:{ModerationDropdown:i.a,RebootButton:v.a,ResetPasswordDialog:_.a,Status:r.a,SecuritySettingsModal:g},data:function(){return{showPrivate:!1,resetPasswordDialogOpen:!1,securitySettingsModalVisible:!1}},computed:{isDesktop:function(){return"desktop"===this.$store.state.app.device},isMobile:function(){return"mobile"===this.$store.state.app.device},isTablet:function(){return"tablet"===this.$store.state.app.device},loading:function(){return this.$store.state.users.loading},statuses:function(){return this.$store.state.userProfile.statuses},statusesLoading:function(){return this.$store.state.userProfile.statusesLoading},user:function(){return this.$store.state.userProfile.user},userProfileLoading:function(){return this.$store.state.userProfile.userProfileLoading},userCredentials:function(){return this.$store.state.userProfile.userCredentials}},mounted:function(){this.$store.dispatch("NeedReboot"),this.$store.dispatch("GetNodeInfo"),this.$store.dispatch("FetchUserProfile",{userId:this.$route.params.id,godmode:!1})},methods:{closeResetPasswordDialog:function(){this.resetPasswordDialogOpen=!1,this.$store.dispatch("RemovePasswordToken")},humanizeTag:function(e){return{"mrf_tag:media-force-nsfw":"Force NSFW","mrf_tag:media-strip":"Strip Media","mrf_tag:force-unlisted":"Force Unlisted","mrf_tag:sandbox":"Sandbox","mrf_tag:disable-remote-subscription":"Disable remote subscription","mrf_tag:disable-any-subscription":"Disable any subscription"}[e]},onTogglePrivate:function(){this.$store.dispatch("FetchUserProfile",{userId:this.$route.params.id,godmode:this.showPrivate})},openResetPasswordDialog:function(){this.resetPasswordDialogOpen=!0},propertyExists:function(e,s){return e[s]}}},f=(t("9IXO"),Object(d.a)(m,function(){var e=this,s=e.$createElement,t=e._self._c||s;return e.userProfileLoading?e._e():t("main",[e.isDesktop||e.isTablet?t("header",{staticClass:"user-page-header"},[t("div",{staticClass:"avatar-name-container"},[e.propertyExists(e.user,"avatar")?t("el-avatar",{attrs:{src:e.user.avatar,size:"large"}}):e._e(),e._v(" "),e.propertyExists(e.user,"nickname")?t("h1",[e._v(e._s(e.user.nickname))]):t("h1",{staticClass:"invalid"},[e._v("("+e._s(e.$t("users.invalidNickname"))+")")]),e._v(" "),e.propertyExists(e.user,"url")?t("a",{attrs:{href:e.user.url,target:"_blank"}},[t("i",{staticClass:"el-icon-top-right",attrs:{title:e.$t("userProfile.openAccountInInstance")}})]):e._e()],1),e._v(" "),t("div",{staticClass:"left-header-container"},[e.propertyExists(e.user,"nickname")?t("moderation-dropdown",{attrs:{user:e.user,page:"userPage"},on:{"open-reset-token-dialog":e.openResetPasswordDialog}}):e._e(),e._v(" "),t("reboot-button")],1)]):e._e(),e._v(" "),e.isMobile?t("div",{staticClass:"user-page-header-container"},[t("header",{staticClass:"user-page-header"},[t("div",{staticClass:"avatar-name-container"},[e.propertyExists(e.user,"avatar")?t("el-avatar",{attrs:{src:e.user.avatar,size:"large"}}):e._e(),e._v(" "),e.propertyExists(e.user,"nickname")?t("h1",[e._v(e._s(e.user.nickname))]):t("h1",{staticClass:"invalid"},[e._v("("+e._s(e.$t("users.invalidNickname"))+")")])],1),e._v(" "),t("reboot-button")],1),e._v(" "),e.propertyExists(e.user,"nickname")?t("moderation-dropdown",{attrs:{user:e.user,page:"userPage"},on:{"open-reset-token-dialog":e.openResetPasswordDialog}}):e._e()],1):e._e(),e._v(" "),t("reset-password-dialog",{attrs:{"reset-password-dialog-open":e.resetPasswordDialogOpen},on:{"close-reset-token-dialog":e.closeResetPasswordDialog}}),e._v(" "),t("div",{staticClass:"user-profile-container"},[t("el-card",{staticClass:"user-profile-card"},[t("div",{staticClass:"el-table el-table--fit el-table--enable-row-hover el-table--enable-row-transition el-table--medium"},[e.propertyExists(e.user,"nickname")?e._e():t("el-tag",{staticClass:"invalid-user-tag",attrs:{type:"info"}},[e._v("\n          "+e._s(e.$t("users.invalidAccount"))+"\n        ")]),e._v(" "),t("table",{staticClass:"user-profile-table"},[t("tbody",[t("tr",{staticClass:"el-table__row"},[t("td",{staticClass:"name-col"},[e._v("ID")]),e._v(" "),t("td",[e._v("\n                "+e._s(e.user.id)+"\n              ")])]),e._v(" "),t("tr",{staticClass:"el-table__row"},[t("td",[e._v(e._s(e.$t("userProfile.actorType")))]),e._v(" "),t("td",[t("el-tag",{attrs:{type:"Person"===e.userCredentials.actor_type?"success":"warning"}},[e._v("\n                  "+e._s(e.userCredentials.actor_type)+"\n                ")])],1)]),e._v(" "),t("tr",{staticClass:"el-table__row"},[t("td",[e._v(e._s(e.$t("userProfile.tags")))]),e._v(" "),t("td",[0!==e.user.tags.length&&e.propertyExists(e.user,"tags")?e._l(e.user.tags,function(s){return t("el-tag",{key:s,staticClass:"user-profile-tag"},[e._v(e._s(e.humanizeTag(s)))])}):t("span",[e._v("—")])],2)]),e._v(" "),t("tr",{staticClass:"el-table__row"},[t("td",[e._v(e._s(e.$t("userProfile.roles")))]),e._v(" "),t("td",[e.user.roles.admin?t("el-tag",{staticClass:"user-profile-tag"},[e._v("\n                  "+e._s(e.$t("users.admin"))+"\n                ")]):e._e(),e._v(" "),e.user.roles.moderator?t("el-tag",{staticClass:"user-profile-tag"},[e._v("\n                  "+e._s(e.$t("users.moderator"))+"\n                ")]):e._e(),e._v(" "),e.propertyExists(e.user,"roles")&&(e.user.roles.moderator||e.user.roles.admin)?e._e():t("span",[e._v("—")])],1)]),e._v(" "),t("tr",{staticClass:"el-table__row"},[t("td",[e._v(e._s(e.$t("userProfile.accountType")))]),e._v(" "),t("td",[e.user.local?t("el-tag",{attrs:{type:"info"}},[e._v(e._s(e.$t("userProfile.local")))]):e._e(),e._v(" "),e.user.local?e._e():t("el-tag",{attrs:{type:"info"}},[e._v(e._s(e.$t("userProfile.external")))])],1)]),e._v(" "),t("tr",{staticClass:"el-table__row"},[t("td",[e._v(e._s(e.$t("userProfile.status")))]),e._v(" "),t("td",[e.user.approval_pending?t("el-tag",{attrs:{type:"info"}},[e._v(e._s(e.$t("userProfile.pending")))]):e._e(),e._v(" "),!e.user.deactivated&!e.user.approval_pending?t("el-tag",{attrs:{type:"success"}},[e._v(e._s(e.$t("userProfile.active")))]):e._e(),e._v(" "),e.user.deactivated?t("el-tag",{attrs:{type:"danger"}},[e._v(e._s(e.$t("userProfile.deactivated")))]):e._e()],1)])])]),e._v(" "),e.user.registration_reason?t("div",[t("div",{staticClass:"reason-label"},[e._v(e._s(e.$t("userProfile.reason")))]),e._v('\n          "'+e._s(e.user.registration_reason)+'"\n        ')]):e._e()],1),e._v(" "),e.propertyExists(e.user,"nickname")?t("el-button",{staticClass:"security-setting-button",attrs:{icon:"el-icon-lock"},on:{click:function(s){e.securitySettingsModalVisible=!0}}},[e._v("\n        "+e._s(e.$t("userProfile.securitySettings.securitySettings"))+"\n      ")]):e._e(),e._v(" "),e.propertyExists(e.user,"nickname")?t("SecuritySettingsModal",{attrs:{user:e.user,visible:e.securitySettingsModalVisible},on:{close:function(s){e.securitySettingsModalVisible=!1}}}):e._e()],1),e._v(" "),t("div",{staticClass:"recent-statuses-container"},[t("h2",{staticClass:"recent-statuses"},[e._v(e._s(e.$t("userProfile.recentStatuses")))]),e._v(" "),t("el-checkbox",{staticClass:"show-private-statuses",on:{change:e.onTogglePrivate},model:{value:e.showPrivate,callback:function(s){e.showPrivate=s},expression:"showPrivate"}},[e._v("\n        "+e._s(e.$t("statuses.showPrivateStatuses"))+"\n      ")]),e._v(" "),e.statusesLoading?e._e():t("el-timeline",{staticClass:"statuses"},[e._l(e.statuses,function(s){return t("el-timeline-item",{key:s.id},[t("status",{attrs:{status:s,account:s.account,"show-checkbox":!1,"user-id":e.user.id,godmode:e.showPrivate}})],1)}),e._v(" "),0===e.statuses.length?t("p",{staticClass:"no-statuses"},[e._v(e._s(e.$t("userProfile.noStatuses")))]):e._e()],2)],1)],1)],1)},[],!1,null,null,null));f.options.__file="show.vue";s.default=f.exports},"53Av":function(e,s,t){"use strict";var r=t("lOBV");t.n(r).a},"9IXO":function(e,s,t){"use strict";var r=t("msq4");t.n(r).a},RnhZ:function(e,s,t){var r={"./af":"K/tc","./af.js":"K/tc","./ar":"jnO4","./ar-dz":"o1bE","./ar-dz.js":"o1bE","./ar-kw":"Qj4J","./ar-kw.js":"Qj4J","./ar-ly":"HP3h","./ar-ly.js":"HP3h","./ar-ma":"CoRJ","./ar-ma.js":"CoRJ","./ar-sa":"gjCT","./ar-sa.js":"gjCT","./ar-tn":"bYM6","./ar-tn.js":"bYM6","./ar.js":"jnO4","./az":"SFxW","./az.js":"SFxW","./be":"H8ED","./be.js":"H8ED","./bg":"hKrs","./bg.js":"hKrs","./bm":"p/rL","./bm.js":"p/rL","./bn":"kEOa","./bn.js":"kEOa","./bo":"0mo+","./bo.js":"0mo+","./br":"aIdf","./br.js":"aIdf","./bs":"JVSJ","./bs.js":"JVSJ","./ca":"1xZ4","./ca.js":"1xZ4","./cs":"PA2r","./cs.js":"PA2r","./cv":"A+xa","./cv.js":"A+xa","./cy":"l5ep","./cy.js":"l5ep","./da":"DxQv","./da.js":"DxQv","./de":"tGlX","./de-at":"s+uk","./de-at.js":"s+uk","./de-ch":"u3GI","./de-ch.js":"u3GI","./de.js":"tGlX","./dv":"WYrj","./dv.js":"WYrj","./el":"jUeY","./el.js":"jUeY","./en-au":"Dmvi","./en-au.js":"Dmvi","./en-ca":"OIYi","./en-ca.js":"OIYi","./en-gb":"Oaa7","./en-gb.js":"Oaa7","./en-ie":"4dOw","./en-ie.js":"4dOw","./en-il":"czMo","./en-il.js":"czMo","./en-in":"7C5Q","./en-in.js":"7C5Q","./en-nz":"b1Dy","./en-nz.js":"b1Dy","./en-sg":"t+mt","./en-sg.js":"t+mt","./eo":"Zduo","./eo.js":"Zduo","./es":"iYuL","./es-do":"CjzT","./es-do.js":"CjzT","./es-us":"Vclq","./es-us.js":"Vclq","./es.js":"iYuL","./et":"7BjC","./et.js":"7BjC","./eu":"D/JM","./eu.js":"D/JM","./fa":"jfSC","./fa.js":"jfSC","./fi":"gekB","./fi.js":"gekB","./fil":"1ppg","./fil.js":"1ppg","./fo":"ByF4","./fo.js":"ByF4","./fr":"nyYc","./fr-ca":"2fjn","./fr-ca.js":"2fjn","./fr-ch":"Dkky","./fr-ch.js":"Dkky","./fr.js":"nyYc","./fy":"cRix","./fy.js":"cRix","./ga":"USCx","./ga.js":"USCx","./gd":"9rRi","./gd.js":"9rRi","./gl":"iEDd","./gl.js":"iEDd","./gom-deva":"qvJo","./gom-deva.js":"qvJo","./gom-latn":"DKr+","./gom-latn.js":"DKr+","./gu":"4MV3","./gu.js":"4MV3","./he":"x6pH","./he.js":"x6pH","./hi":"3E1r","./hi.js":"3E1r","./hr":"S6ln","./hr.js":"S6ln","./hu":"WxRl","./hu.js":"WxRl","./hy-am":"1rYy","./hy-am.js":"1rYy","./id":"UDhR","./id.js":"UDhR","./is":"BVg3","./is.js":"BVg3","./it":"bpih","./it-ch":"bxKX","./it-ch.js":"bxKX","./it.js":"bpih","./ja":"B55N","./ja.js":"B55N","./jv":"tUCv","./jv.js":"tUCv","./ka":"IBtZ","./ka.js":"IBtZ","./kk":"bXm7","./kk.js":"bXm7","./km":"6B0Y","./km.js":"6B0Y","./kn":"PpIw","./kn.js":"PpIw","./ko":"Ivi+","./ko.js":"Ivi+","./ku":"JCF/","./ku.js":"JCF/","./ky":"lgnt","./ky.js":"lgnt","./lb":"RAwQ","./lb.js":"RAwQ","./lo":"sp3z","./lo.js":"sp3z","./lt":"JvlW","./lt.js":"JvlW","./lv":"uXwI","./lv.js":"uXwI","./me":"KTz0","./me.js":"KTz0","./mi":"aIsn","./mi.js":"aIsn","./mk":"aQkU","./mk.js":"aQkU","./ml":"AvvY","./ml.js":"AvvY","./mn":"lYtQ","./mn.js":"lYtQ","./mr":"Ob0Z","./mr.js":"Ob0Z","./ms":"6+QB","./ms-my":"ZAMP","./ms-my.js":"ZAMP","./ms.js":"6+QB","./mt":"G0Uy","./mt.js":"G0Uy","./my":"honF","./my.js":"honF","./nb":"bOMt","./nb.js":"bOMt","./ne":"OjkT","./ne.js":"OjkT","./nl":"+s0g","./nl-be":"2ykv","./nl-be.js":"2ykv","./nl.js":"+s0g","./nn":"uEye","./nn.js":"uEye","./oc-lnc":"Fnuy","./oc-lnc.js":"Fnuy","./pa-in":"8/+R","./pa-in.js":"8/+R","./pl":"jVdC","./pl.js":"jVdC","./pt":"8mBD","./pt-br":"0tRk","./pt-br.js":"0tRk","./pt.js":"8mBD","./ro":"lyxo","./ro.js":"lyxo","./ru":"lXzo","./ru.js":"lXzo","./sd":"Z4QM","./sd.js":"Z4QM","./se":"//9w","./se.js":"//9w","./si":"7aV9","./si.js":"7aV9","./sk":"e+ae","./sk.js":"e+ae","./sl":"gVVK","./sl.js":"gVVK","./sq":"yPMs","./sq.js":"yPMs","./sr":"zx6S","./sr-cyrl":"E+lV","./sr-cyrl.js":"E+lV","./sr.js":"zx6S","./ss":"Ur1D","./ss.js":"Ur1D","./sv":"X709","./sv.js":"X709","./sw":"dNwA","./sw.js":"dNwA","./ta":"PeUW","./ta.js":"PeUW","./te":"XLvN","./te.js":"XLvN","./tet":"V2x9","./tet.js":"V2x9","./tg":"Oxv6","./tg.js":"Oxv6","./th":"EOgW","./th.js":"EOgW","./tk":"Wv91","./tk.js":"Wv91","./tl-ph":"Dzi0","./tl-ph.js":"Dzi0","./tlh":"z3Vd","./tlh.js":"z3Vd","./tr":"DoHr","./tr.js":"DoHr","./tzl":"z1FC","./tzl.js":"z1FC","./tzm":"wQk9","./tzm-latn":"tT3J","./tzm-latn.js":"tT3J","./tzm.js":"wQk9","./ug-cn":"YRex","./ug-cn.js":"YRex","./uk":"raLr","./uk.js":"raLr","./ur":"UpQW","./ur.js":"UpQW","./uz":"Loxo","./uz-latn":"AQ68","./uz-latn.js":"AQ68","./uz.js":"Loxo","./vi":"KSF8","./vi.js":"KSF8","./x-pseudo":"/X5v","./x-pseudo.js":"/X5v","./yo":"fzPg","./yo.js":"fzPg","./zh-cn":"XDpg","./zh-cn.js":"XDpg","./zh-hk":"SatO","./zh-hk.js":"SatO","./zh-mo":"OmwH","./zh-mo.js":"OmwH","./zh-tw":"kOpN","./zh-tw.js":"kOpN"};function i(e){var s=a(e);return t(s)}function a(e){if(!t.o(r,e)){var s=new Error("Cannot find module '"+e+"'");throw s.code="MODULE_NOT_FOUND",s}return r[e]}i.keys=function(){return Object.keys(r)},i.resolve=a,e.exports=i,i.id="RnhZ"},WjBP:function(e,s,t){"use strict";var r={name:"ResetPasswordDialog",props:{resetPasswordDialogOpen:{type:Boolean,default:!1}},computed:{dialogOpen:function(){return this.resetPasswordDialogOpen},loading:function(){return this.$store.state.users.loading},passwordResetLink:function(){return this.$store.state.users.passwordResetToken.link},passwordResetToken:function(){return this.$store.state.users.passwordResetToken.token}},methods:{closeResetPasswordDialog:function(){this.$emit("close-reset-token-dialog")}}},i=t("KHd+"),a=Object(i.a)(r,function(){var e=this,s=e.$createElement,t=e._self._c||s;return t("el-dialog",{directives:[{name:"loading",rawName:"v-loading",value:e.loading,expression:"loading"}],attrs:{visible:e.dialogOpen,title:e.$t("users.passwordResetTokenCreated"),"custom-class":"password-reset-token-dialog"},on:{close:e.closeResetPasswordDialog}},[t("div",[t("p",{staticClass:"password-reset-token"},[e._v(e._s(e.$t("users.passwordResetTokenGenerated"))+" "+e._s(e.passwordResetToken))]),e._v(" "),t("p",[e._v(e._s(e.$t("users.linkToResetPassword"))+"\n      "),t("a",{staticClass:"reset-password-link",attrs:{href:e.passwordResetLink,target:"_blank"}},[e._v(e._s(e.passwordResetLink))])])])])},[],!1,null,null,null);a.options.__file="ResetPasswordDialog.vue";s.a=a.exports},lOBV:function(e,s,t){},msq4:function(e,s,t){},tPM3:function(e,s,t){"use strict";var r={name:"ModerationDropdown",props:{user:{type:Object,default:function(){return{}}},page:{type:String,default:"users"},statusId:{type:String,default:""}},computed:{actorType:{get:function(){return this.user.actor_type},set:function(e){this.$store.dispatch("UpdateActorType",{user:this.user,type:e,_userId:this.user.id,_statusId:this.statusId})}},isDesktop:function(){return"desktop"===this.$store.state.app.device}},methods:{disableMfa:function(e){this.$store.dispatch("DisableMfa",e)},getPasswordResetToken:function(e){this.$emit("open-reset-token-dialog"),this.$store.dispatch("GetPasswordResetToken",e)},handleConfirmationResend:function(e){this.$store.dispatch("ResendConfirmationEmail",[e])},handleDeletion:function(e){var s=this;this.$confirm(this.$t("users.deleteUserConfirmation"),{confirmButtonText:"Delete",cancelButtonText:"Cancel",type:"warning"}).then(function(){s.$store.dispatch("DeleteUsers",{users:[e],_userId:e.id})}).catch(function(){s.$message({type:"info",message:"Delete canceled"})})},handleAccountApproval:function(e){this.$store.dispatch("ApproveUsersAccount",{users:[e],_userId:e.id,_statusId:this.statusId})},handleAccountRejection:function(e){var s=this;this.$confirm(this.$t("users.rejectAccountConfirmation"),{confirmButtonText:"Reject",cancelButtonText:"Cancel",type:"warning"}).then(function(){s.$store.dispatch("DeleteUsers",{users:[e],_userId:e.id})}).catch(function(){s.$message({type:"info",message:"Reject canceled"})})},handleEmailConfirmation:function(e){this.$store.dispatch("ConfirmUsersEmail",{users:[e],_userId:e.id,_statusId:this.statusId})},requirePasswordReset:function(e){this.$store.state.user.nodeInfo.metadata.mailerEnabled?this.$store.dispatch("RequirePasswordReset",[e]):this.$alert(this.$t("users.mailerMustBeEnabled"),"Error",{type:"error"})},showAdminAction:function(e){var s=e.local,t=e.id;return s&&this.showDeactivatedButton(t)},showDeactivatedButton:function(e){return this.$store.state.user.id!==e},toggleActivation:function(e){e.deactivated?this.$store.dispatch("ActivateUsers",{users:[e],_userId:e.id}):this.$store.dispatch("DeactivateUsers",{users:[e],_userId:e.id})},toggleTag:function(e,s){e.tags.includes(s)?this.$store.dispatch("RemoveTag",{users:[e],tag:s,_userId:e.id,_statusId:this.statusId}):this.$store.dispatch("AddTag",{users:[e],tag:s,_userId:e.id,_statusId:this.statusId})},toggleUserRight:function(e,s){e.roles[s]?this.$store.dispatch("DeleteRight",{users:[e],right:s,_userId:e.id,_statusId:this.statusId}):this.$store.dispatch("AddRight",{users:[e],right:s,_userId:e.id,_statusId:this.statusId})}}},i=(t("53Av"),t("KHd+")),a=Object(i.a)(r,function(){var e=this,s=e.$createElement,t=e._self._c||s;return t("el-dropdown",{attrs:{"hide-on-click":!1,size:"small",trigger:"click",placement:"top-start"},nativeOn:{click:function(e){e.stopPropagation()}}},[t("div",["users"===e.page?t("el-button",{staticClass:"el-dropdown-link",attrs:{type:"text"}},[e._v("\n      "+e._s(e.$t("users.moderation"))+"\n      "),e.isDesktop?t("i",{staticClass:"el-icon-arrow-down el-icon--right"}):e._e()]):e._e(),e._v(" "),"userPage"===e.page||"statusPage"===e.page?t("el-button",{staticClass:"moderate-user-button"},[t("span",{staticClass:"moderate-user-button-container"},[t("span",[t("i",{staticClass:"el-icon-edit"}),e._v("\n          "+e._s(e.$t("users.moderateUser"))+"\n        ")]),e._v(" "),t("i",{staticClass:"el-icon-arrow-down el-icon--right"})])]):e._e()],1),e._v(" "),t("el-dropdown-menu",{attrs:{slot:"dropdown"},slot:"dropdown"},[t("el-dropdown-item",{staticClass:"actor-type-dropdown"},[t("el-select",{staticClass:"actor-type-select",attrs:{placeholder:e.$t("userProfile.actorType")},model:{value:e.actorType,callback:function(s){e.actorType=s},expression:"actorType"}},[t("el-option",{attrs:{label:e.$t("users.service"),value:"Service"}}),e._v(" "),t("el-option",{attrs:{label:e.$t("users.person"),value:"Person"}})],1)],1),e._v(" "),e.showAdminAction(e.user)?t("el-dropdown-item",{attrs:{divided:""},nativeOn:{click:function(s){return e.toggleUserRight(e.user,"admin")}}},[e._v("\n      "+e._s(e.user.roles.admin?e.$t("users.revokeAdmin"):e.$t("users.grantAdmin"))+"\n    ")]):e._e(),e._v(" "),e.showAdminAction(e.user)?t("el-dropdown-item",{nativeOn:{click:function(s){return e.toggleUserRight(e.user,"moderator")}}},[e._v("\n      "+e._s(e.user.roles.moderator?e.$t("users.revokeModerator"):e.$t("users.grantModerator"))+"\n    ")]):e._e(),e._v(" "),e.showDeactivatedButton(e.user.id)&&"statusPage"!==e.page?t("el-dropdown-item",{attrs:{divided:e.showAdminAction(e.user)},nativeOn:{click:function(s){return e.toggleActivation(e.user)}}},[e._v("\n      "+e._s(e.user.deactivated?e.$t("users.activateAccount"):e.$t("users.deactivateAccount"))+"\n    ")]):e._e(),e._v(" "),e.showDeactivatedButton(e.user.id)&&"statusPage"!==e.page?t("el-dropdown-item",{nativeOn:{click:function(s){return e.handleDeletion(e.user)}}},[e._v("\n      "+e._s(e.$t("users.deleteAccount"))+"\n    ")]):e._e(),e._v(" "),e.user.local&&e.user.approval_pending?t("el-dropdown-item",{attrs:{divided:""},nativeOn:{click:function(s){return e.handleAccountApproval(e.user)}}},[e._v("\n      "+e._s(e.$t("users.approveAccount"))+"\n    ")]):e._e(),e._v(" "),e.user.local&&e.user.approval_pending?t("el-dropdown-item",{nativeOn:{click:function(s){return e.handleAccountRejection(e.user)}}},[e._v("\n      "+e._s(e.$t("users.rejectAccount"))+"\n    ")]):e._e(),e._v(" "),e.user.local&&e.user.confirmation_pending?t("el-dropdown-item",{attrs:{divided:""},nativeOn:{click:function(s){return e.handleEmailConfirmation(e.user)}}},[e._v("\n      "+e._s(e.$t("users.confirmAccount"))+"\n    ")]):e._e(),e._v(" "),e.user.local&&e.user.confirmation_pending?t("el-dropdown-item",{nativeOn:{click:function(s){return e.handleConfirmationResend(e.user)}}},[e._v("\n      "+e._s(e.$t("users.resendConfirmation"))+"\n    ")]):e._e(),e._v(" "),t("el-dropdown-item",{class:{"active-tag":e.user.tags.includes("mrf_tag:media-force-nsfw")},attrs:{divided:e.showAdminAction(e.user)},nativeOn:{click:function(s){return e.toggleTag(e.user,"mrf_tag:media-force-nsfw")}}},[e._v("\n      "+e._s(e.$t("users.forceNsfw"))+"\n      "),e.user.tags.includes("mrf_tag:media-force-nsfw")?t("i",{staticClass:"el-icon-check"}):e._e()]),e._v(" "),t("el-dropdown-item",{class:{"active-tag":e.user.tags.includes("mrf_tag:media-strip")},nativeOn:{click:function(s){return e.toggleTag(e.user,"mrf_tag:media-strip")}}},[e._v("\n      "+e._s(e.$t("users.stripMedia"))+"\n      "),e.user.tags.includes("mrf_tag:media-strip")?t("i",{staticClass:"el-icon-check"}):e._e()]),e._v(" "),t("el-dropdown-item",{class:{"active-tag":e.user.tags.includes("mrf_tag:force-unlisted")},nativeOn:{click:function(s){return e.toggleTag(e.user,"mrf_tag:force-unlisted")}}},[e._v("\n      "+e._s(e.$t("users.forceUnlisted"))+"\n      "),e.user.tags.includes("mrf_tag:force-unlisted")?t("i",{staticClass:"el-icon-check"}):e._e()]),e._v(" "),t("el-dropdown-item",{class:{"active-tag":e.user.tags.includes("mrf_tag:sandbox")},nativeOn:{click:function(s){return e.toggleTag(e.user,"mrf_tag:sandbox")}}},[e._v("\n      "+e._s(e.$t("users.sandbox"))+"\n      "),e.user.tags.includes("mrf_tag:sandbox")?t("i",{staticClass:"el-icon-check"}):e._e()]),e._v(" "),e.user.local?t("el-dropdown-item",{class:{"active-tag":e.user.tags.includes("mrf_tag:disable-remote-subscription")},nativeOn:{click:function(s){return e.toggleTag(e.user,"mrf_tag:disable-remote-subscription")}}},[e._v("\n      "+e._s(e.$t("users.disableRemoteSubscription"))+"\n      "),e.user.tags.includes("mrf_tag:disable-remote-subscription")?t("i",{staticClass:"el-icon-check"}):e._e()]):e._e(),e._v(" "),e.user.local?t("el-dropdown-item",{class:{"active-tag":e.user.tags.includes("mrf_tag:disable-any-subscription")},nativeOn:{click:function(s){return e.toggleTag(e.user,"mrf_tag:disable-any-subscription")}}},[e._v("\n      "+e._s(e.$t("users.disableAnySubscription"))+"\n      "),e.user.tags.includes("mrf_tag:disable-any-subscription")?t("i",{staticClass:"el-icon-check"}):e._e()]):e._e(),e._v(" "),e.user.local?t("el-dropdown-item",{attrs:{divided:""},nativeOn:{click:function(s){return e.getPasswordResetToken(e.user.nickname)}}},[e._v("\n      "+e._s(e.$t("users.getPasswordResetToken"))+"\n    ")]):e._e(),e._v(" "),e.user.local?t("el-dropdown-item",{nativeOn:{click:function(s){return e.requirePasswordReset(e.user)}}},[e._v("\n      "+e._s(e.$t("users.requirePasswordReset"))+"\n    ")]):e._e(),e._v(" "),e.user.local?t("el-dropdown-item",{nativeOn:{click:function(s){return e.disableMfa(e.user.nickname)}}},[e._v("\n      "+e._s(e.$t("users.disableMfa"))+"\n    ")]):e._e()],1)],1)},[],!1,null,null,null);a.options.__file="ModerationDropdown.vue";s.a=a.exports}}]);
//# sourceMappingURL=chunk-6e8c.bb92565e.js.map