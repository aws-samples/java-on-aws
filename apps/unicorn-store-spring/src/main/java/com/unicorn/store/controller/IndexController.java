package com.unicorn.store.controller;

import com.unicorn.store.config.ReleaseInfo;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class IndexController {

    private final ReleaseInfo releaseInfo;

    public IndexController(ReleaseInfo releaseInfo) {
        this.releaseInfo = releaseInfo;
    }

    @GetMapping("/")
    public String index(Model model) {
        model.addAttribute("version", releaseInfo.getVersion());
        model.addAttribute("versionUrl", releaseInfo.getVersionUrl());
        model.addAttribute("deploymentTime", releaseInfo.getDeploymentTime());
        model.addAttribute("commit", releaseInfo.getCommit());
        model.addAttribute("commitUrl", releaseInfo.getCommitUrl());
        model.addAttribute("pod", releaseInfo.getPod());
        model.addAttribute("environment", releaseInfo.getEnvironment());
        model.addAttribute("deploymentType", releaseInfo.getDeploymentType());
        model.addAttribute("deploymentTypeColor", releaseInfo.getDeploymentTypeColor());
        model.addAttribute("deploymentTypeLabel", releaseInfo.getDeploymentTypeLabel());
        model.addAttribute("pageTitle", releaseInfo.getPageTitle());
        return "index";
    }
}
