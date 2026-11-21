# null leaves the Dockerfile's ARG default in place
variable "WINE_BRANCH" { default = null }
variable "WINE_VERSION" { default = null }
variable "MSVC_VERSION" { default = null }
variable "WIN_SDK_VERSION" { default = null }
variable "UE_COMMITISH" { default = null }
variable "UE_VERSION" { default = null }
variable "WWISE_SDK_VERSION" { default = null }

group "default" {
  targets = ["base", "ue-build", "sml-build"]
}

target "base" {
  dockerfile = "base.Dockerfile"
  args = {
    WINE_BRANCH     = WINE_BRANCH
    WINE_VERSION    = WINE_VERSION
    MSVC_VERSION    = MSVC_VERSION
    WIN_SDK_VERSION = WIN_SDK_VERSION
  }
}

# BASE_IMAGE=base resolves to the named context below, so base is consumed
# straight from this build instead of being pulled from a registry
target "ue-build" {
  dockerfile = "ue-build.Dockerfile"
  contexts   = { base = "target:base" }
  args = {
    BASE_IMAGE   = "base"
    UE_COMMITISH = UE_COMMITISH
  }
  secret = ["id=GH_TOKEN,env=GH_TOKEN"]
}

target "sml-build" {
  dockerfile = "sml-build.Dockerfile"
  contexts   = { base = "target:base" }
  args = {
    BASE_IMAGE        = "base"
    UE_VERSION        = UE_VERSION
    WWISE_SDK_VERSION = WWISE_SDK_VERSION
  }
  secret = [
    "id=GH_TOKEN,env=GH_TOKEN",
    "id=WWISE_EMAIL,env=WWISE_EMAIL",
    "id=WWISE_PASSWORD,env=WWISE_PASSWORD",
  ]
}
